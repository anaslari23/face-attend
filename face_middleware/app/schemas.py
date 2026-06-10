from datetime import datetime

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str
    embedding_backend: str
    model_loaded: bool
    database_connected: bool
    embedding_count: int
    antispoofing: str
    antispoofing_enabled: bool = False
    antispoofing_model_loaded: bool = False
    antispoofing_threshold: float | None = None


class MatchEmployee(BaseModel):
    employee_id: int
    employee_name: str | None = None


class MatchResponse(BaseModel):
    matched: bool
    confidence: float = Field(ge=-1.0, le=1.0)
    threshold: float
    review_threshold: float | None = None
    timestamp: datetime
    employee: MatchEmployee | None = None
    reason: str | None = None
    second_best_confidence: float | None = Field(default=None, ge=-1.0, le=1.0)
    embedding_source: str | None = None
    embedding_id: int | None = None
    needs_review: bool = False
    review_embedding_id: int | None = None
    liveness_passed: bool | None = None
    liveness_score: float | None = None
    spoof_score: float | None = None


class FaceBox(BaseModel):
    left: float
    top: float
    right: float
    bottom: float


class RegisterResponse(BaseModel):
    employee_id: int
    employee_name: str | None = None
    frames_received: int
    frames_accepted: int
    embedding_dimension: int
    registered_at: datetime
    detection_score: float | None = None
    face_box: FaceBox | None = None
    face_ratio: float | None = None
    blur_variance: float | None = None


class MultiFaceMatch(BaseModel):
    matched: bool
    confidence: float = Field(ge=-1.0, le=1.0)
    threshold: float
    review_threshold: float | None = None
    bbox: FaceBox
    employee: MatchEmployee | None = None
    reason: str | None = None
    second_best_confidence: float | None = Field(default=None, ge=-1.0, le=1.0)
    embedding_source: str | None = None
    embedding_id: int | None = None
    needs_review: bool = False
    review_embedding_id: int | None = None
    liveness_passed: bool | None = None
    liveness_score: float | None = None
    spoof_score: float | None = None


class MultiMatchResponse(BaseModel):
    timestamp: datetime
    image_width: int
    image_height: int
    faces: list[MultiFaceMatch]


class DeleteResponse(BaseModel):
    employee_id: int
    deleted: bool


class ApproveEmbeddingResponse(BaseModel):
    employee_id: int
    embedding_id: int
    approved: bool
