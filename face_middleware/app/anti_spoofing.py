from pathlib import Path
import sys

import cv2
import numpy as np
import onnxruntime as ort

from .config import Settings
from .errors import FacePipelineError


class AntiSpoofingService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._session: ort.InferenceSession | None = None
        self._input_name: str | None = None
        self._input_shape: list[int | str | None] | None = None
        self._torch_models = None

    @property
    def mode(self) -> str:
        if self.settings.anti_spoofing_enabled:
            if self.settings.allow_antispoof_stub:
                return "stub"
            return "ready" if self.model_loaded else "required"
        return "disabled"

    @property
    def enabled(self) -> bool:
        return self.settings.anti_spoofing_enabled

    @property
    def model_loaded(self) -> bool:
        if not self.settings.anti_spoofing_enabled or self.settings.allow_antispoof_stub:
            return self.settings.anti_spoofing_enabled
        try:
            model_path = Path(self.settings.antispoof_model_path)
            if model_path.is_dir() or model_path.suffix.lower() == ".pth":
                self._ensure_torch_models()
            else:
                self._ensure_session()
        except FacePipelineError:
            return False
        return True

    @property
    def threshold(self) -> float:
        return self.settings.antispoof_threshold

    def validate(self, image: np.ndarray, bbox: tuple[float, float, float, float] | None = None) -> float | None:
        if not self.settings.anti_spoofing_enabled:
            raise FacePipelineError(
                "anti_spoofing_unavailable",
                "Anti-spoofing is required for attendance matching but is disabled.",
                503,
            )
        if self.settings.allow_antispoof_stub:
            raise FacePipelineError(
                "anti_spoofing_unavailable",
                "Anti-spoofing is required for attendance matching but the stub mode is enabled.",
                503,
            )

        model_path = Path(self.settings.antispoof_model_path)
        if model_path.is_dir() or model_path.suffix.lower() == ".pth":
            live_score = self._validate_torch(image, bbox)
            if live_score < self.settings.antispoof_threshold:
                raise FacePipelineError("spoof_detected", "Photo or screen detected.", 422)
            return live_score

        session = self._ensure_session()
        input_name = self._input_name
        if not input_name:
            raise self._unavailable()

        live_score = self._live_score(session.run(None, {input_name: self._preprocess(image)}))
        if live_score < self.settings.antispoof_threshold:
            raise FacePipelineError(
                "spoof_detected",
                "Photo or screen detected.",
                422,
            )
        return live_score

    def _validate_torch(self, image: np.ndarray, bbox: tuple[float, float, float, float] | None) -> float:
        if bbox is None:
            raise FacePipelineError("anti_spoofing_unavailable", "Anti-spoofing requires a detected face box.", 503)
        models = self._ensure_torch_models()
        if not models:
            raise self._unavailable()

        prediction = np.zeros((1, 3), dtype=np.float32)
        for model, height, width, scale, torch in models:
            patch = self._crop_for_model(image, bbox, scale, width, height)
            tensor = torch.from_numpy(patch.transpose(2, 0, 1)).float().unsqueeze(0)
            with torch.no_grad():
                prediction += torch.softmax(model(tensor), dim=1).cpu().numpy()
        prediction /= float(len(models))
        # Silent-Face labels class index 1 as live/real.
        return float(prediction[0][1])

    def _ensure_torch_models(self):
        if self._torch_models is not None:
            return self._torch_models
        model_path = Path(self.settings.antispoof_model_path)
        model_files = sorted(model_path.glob("*.pth")) if model_path.is_dir() else [model_path]
        if not model_files or not all(path.exists() for path in model_files):
            raise self._unavailable()
        try:
            import torch
        except Exception as error:  # pragma: no cover - depends on local runtime
            raise self._unavailable() from error

        model_dir = model_path if model_path.is_dir() else model_path.parent
        if str(model_dir) not in sys.path:
            sys.path.insert(0, str(model_dir))
        from MiniFASNet import MiniFASNetV1, MiniFASNetV1SE, MiniFASNetV2, MiniFASNetV2SE

        mapping = {
            "MiniFASNetV1": MiniFASNetV1,
            "MiniFASNetV2": MiniFASNetV2,
            "MiniFASNetV1SE": MiniFASNetV1SE,
            "MiniFASNetV2SE": MiniFASNetV2SE,
        }
        loaded = []
        for path in model_files:
            height, width, model_type, scale = self._parse_silent_face_model_name(path.name)
            kernel = ((height + 15) // 16, (width + 15) // 16)
            model = mapping[model_type](conv6_kernel=kernel)
            state_dict = torch.load(str(path), map_location="cpu")
            first_key = next(iter(state_dict))
            if first_key.startswith("module."):
                state_dict = {key[7:]: value for key, value in state_dict.items()}
            model.load_state_dict(state_dict)
            model.eval()
            loaded.append((model, height, width, scale, torch))
        self._torch_models = loaded
        return loaded

    def _crop_for_model(
        self,
        image: np.ndarray,
        bbox: tuple[float, float, float, float],
        scale: float | None,
        width: int,
        height: int,
    ) -> np.ndarray:
        if scale is None:
            return cv2.resize(image, (width, height))
        x1, y1, x2, y2 = bbox
        box = [float(x1), float(y1), max(1.0, float(x2 - x1)), max(1.0, float(y2 - y1))]
        src_h, src_w = image.shape[:2]
        scale = min((src_h - 1) / box[3], min((src_w - 1) / box[2], scale))
        new_width = box[2] * scale
        new_height = box[3] * scale
        center_x = box[2] / 2 + box[0]
        center_y = box[3] / 2 + box[1]
        left = center_x - new_width / 2
        top = center_y - new_height / 2
        right = center_x + new_width / 2
        bottom = center_y + new_height / 2
        if left < 0:
            right -= left
            left = 0
        if top < 0:
            bottom -= top
            top = 0
        if right > src_w - 1:
            left -= right - src_w + 1
            right = src_w - 1
        if bottom > src_h - 1:
            top -= bottom - src_h + 1
            bottom = src_h - 1
        crop = image[int(top) : int(bottom) + 1, int(left) : int(right) + 1]
        if crop.size == 0:
            raise FacePipelineError("face_not_clear", "Face not clear.")
        return cv2.resize(crop, (width, height)).astype(np.float32)

    def _parse_silent_face_model_name(self, model_name: str) -> tuple[int, int, str, float | None]:
        info = model_name.split("_")[0:-1]
        height, width = info[-1].split("x")
        model_type = model_name.split(".pth")[0].split("_")[-1]
        scale = None if info[0] == "org" else float(info[0])
        return int(height), int(width), model_type, scale

    def _ensure_session(self) -> ort.InferenceSession:
        if self._session is not None:
            return self._session
        model_path = Path(self.settings.antispoof_model_path)
        if not model_path.exists():
            raise self._unavailable()
        try:
            self._session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        except Exception as error:  # pragma: no cover - depends on local runtime/model
            raise self._unavailable() from error
        model_input = self._session.get_inputs()[0]
        self._input_name = model_input.name
        self._input_shape = list(model_input.shape)
        return self._session

    def _preprocess(self, image: np.ndarray) -> np.ndarray:
        shape = self._input_shape or [1, 3, 80, 80]
        height = self._shape_dim(shape, -2, 80)
        width = self._shape_dim(shape, -1, 80)
        resized = cv2.resize(image, (width, height), interpolation=cv2.INTER_AREA)
        rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        if len(shape) == 4 and self._shape_dim(shape, 1, 3) == 3:
            return np.expand_dims(np.transpose(rgb, (2, 0, 1)), axis=0)
        return np.expand_dims(rgb, axis=0)

    def _live_score(self, outputs: list[np.ndarray]) -> float:
        if not outputs:
            raise self._unavailable()
        values = np.asarray(outputs[0], dtype=np.float32).reshape(-1)
        if values.size == 0:
            raise self._unavailable()
        if values.size == 1:
            return float(values[0])
        if np.all(values >= 0) and np.all(values <= 1) and 0.95 <= float(np.sum(values)) <= 1.05:
            return float(values[-1])
        exp = np.exp(values - np.max(values))
        probs = exp / np.sum(exp)
        return float(probs[-1])

    def _shape_dim(self, shape: list[int | str | None], index: int, default: int) -> int:
        try:
            value = shape[index]
        except IndexError:
            return default
        return value if isinstance(value, int) and value > 0 else default

    def _unavailable(self) -> FacePipelineError:
        return FacePipelineError(
            "anti_spoofing_unavailable",
            "Anti-spoofing is required but no production anti-spoofing model is configured.",
            503,
        )
