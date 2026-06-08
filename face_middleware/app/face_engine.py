from abc import ABC, abstractmethod
from hashlib import sha512

import cv2
import numpy as np

from .config import Settings
from .errors import FacePipelineError
from .image_processing import apply_clahe


class FaceEngine(ABC):
    @property
    @abstractmethod
    def model_loaded(self) -> bool:
        raise NotImplementedError

    @abstractmethod
    def embed(self, image: np.ndarray) -> np.ndarray:
        raise NotImplementedError


class InsightFaceEngine(FaceEngine):
    def __init__(self, settings: Settings):
        self.settings = settings
        self._app = None
        self._load_error: str | None = None
        self._load_model()

    @property
    def model_loaded(self) -> bool:
        return self._app is not None

    def _load_model(self) -> None:
        try:
            from insightface.app import FaceAnalysis

            app = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])
            app.prepare(ctx_id=-1, det_thresh=self.settings.detection_threshold, det_size=(640, 640))
            self._app = app
        except Exception as error:  # pragma: no cover - depends on native model runtime
            self._load_error = str(error)
            self._app = None

    def embed(self, image: np.ndarray) -> np.ndarray:
        if self._app is None:
            raise FacePipelineError(
                "model_unavailable",
                f"InsightFace model is unavailable: {self._load_error or 'unknown error'}",
                503,
            )

        enhanced = apply_clahe(image)
        faces = self._app.get(enhanced)
        if not faces:
            raise FacePipelineError("no_face_detected", "No face detected.")
        if len(faces) > 1:
            raise FacePipelineError("multiple_faces_detected", "Multiple faces detected.")

        face = faces[0]
        det_score = float(getattr(face, "det_score", 0.0))
        if det_score < self.settings.detection_threshold:
            raise FacePipelineError("low_detection_score", "Face detection score is below threshold.")

        # InsightFace normed_embedding is already L2-normalized.
        embedding = np.asarray(face.normed_embedding, dtype=np.float32)
        return normalize_embedding(embedding)


class DevFaceEngine(FaceEngine):
    """Deterministic fallback for API tests only; not real face recognition."""

    @property
    def model_loaded(self) -> bool:
        return True

    def embed(self, image: np.ndarray) -> np.ndarray:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        digest = sha512(gray.tobytes()).digest()
        values = np.frombuffer(digest * 8, dtype=np.uint8).astype(np.float32)[:512]
        return normalize_embedding(values)


def normalize_embedding(embedding: np.ndarray) -> np.ndarray:
    norm = float(np.linalg.norm(embedding))
    if norm == 0:
        raise FacePipelineError("empty_embedding", "Generated embedding is empty.")
    return (embedding / norm).astype(np.float32)


def build_face_engine(settings: Settings) -> FaceEngine:
    if settings.embedding_backend == "dev":
        return DevFaceEngine()
    return InsightFaceEngine(settings)
