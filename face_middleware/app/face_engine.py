from abc import ABC, abstractmethod
from dataclasses import dataclass
from hashlib import sha512

import cv2
import numpy as np

from .config import Settings
from .errors import FacePipelineError
from .image_processing import apply_clahe


@dataclass(frozen=True)
class FaceEmbedding:
    embedding: np.ndarray
    bbox: tuple[float, float, float, float]
    det_score: float


class FaceEngine(ABC):
    @property
    @abstractmethod
    def model_loaded(self) -> bool:
        raise NotImplementedError

    @abstractmethod
    def embed(self, image: np.ndarray) -> np.ndarray:
        raise NotImplementedError

    @abstractmethod
    def embed_many(self, image: np.ndarray) -> list[FaceEmbedding]:
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
        faces = self.embed_many(image)
        if not faces:
            raise FacePipelineError("no_face_detected", "No face detected.")
        if len(faces) > 1:
            raise FacePipelineError("multiple_faces_detected", "Multiple faces detected.")
        return faces[0].embedding

    def embed_many(self, image: np.ndarray) -> list[FaceEmbedding]:
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
        detected: list[FaceEmbedding] = []
        for face in faces:
            det_score = float(getattr(face, "det_score", 0.0))
            if det_score < self.settings.detection_threshold:
                continue
            self._validate_face_quality(enhanced, face)

            # InsightFace normed_embedding is already L2-normalized.
            embedding = normalize_embedding(np.asarray(face.normed_embedding, dtype=np.float32))
            bbox = tuple(float(value) for value in np.asarray(face.bbox, dtype=np.float32).tolist()[:4])
            detected.append(FaceEmbedding(embedding=embedding, bbox=bbox, det_score=det_score))
        if not detected:
            raise FacePipelineError("low_detection_score", "Face detection score is below threshold.")
        return detected

    def _validate_face_quality(self, image: np.ndarray, face) -> None:
        bbox = np.asarray(getattr(face, "bbox", []), dtype=np.float32)
        if bbox.shape[0] < 4:
            raise FacePipelineError("face_not_clear", "Face not clear.")

        height, width = image.shape[:2]
        face_width = max(0.0, float(bbox[2] - bbox[0]))
        face_height = max(0.0, float(bbox[3] - bbox[1]))
        short_side = float(max(1, min(width, height)))
        face_ratio = max(face_width, face_height) / short_side
        if face_ratio < self.settings.min_face_ratio:
            raise FacePipelineError("face_too_small", "Move closer to the camera.")
        if face_ratio > self.settings.max_face_ratio:
            raise FacePipelineError("face_too_large", "Move slightly back.")

        x1 = max(0, int(bbox[0]))
        y1 = max(0, int(bbox[1]))
        x2 = min(width, int(bbox[2]))
        y2 = min(height, int(bbox[3]))
        if x2 <= x1 or y2 <= y1:
            raise FacePipelineError("face_not_clear", "Face not clear.")

        gray = cv2.cvtColor(image[y1:y2, x1:x2], cv2.COLOR_BGR2GRAY)
        blur_variance = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        if blur_variance < self.settings.min_blur_variance:
            raise FacePipelineError("face_not_clear", "Face not clear.")


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

    def embed_many(self, image: np.ndarray) -> list[FaceEmbedding]:
        height, width = image.shape[:2]
        return [
            FaceEmbedding(
                embedding=self.embed(image),
                bbox=(0.0, 0.0, float(width), float(height)),
                det_score=1.0,
            )
        ]


def normalize_embedding(embedding: np.ndarray) -> np.ndarray:
    norm = float(np.linalg.norm(embedding))
    if norm == 0:
        raise FacePipelineError("empty_embedding", "Generated embedding is empty.")
    return (embedding / norm).astype(np.float32)


def build_face_engine(settings: Settings) -> FaceEngine:
    if settings.embedding_backend == "dev":
        return DevFaceEngine()
    return InsightFaceEngine(settings)
