from datetime import datetime

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str
    embedding_backend: str
    model_loaded: bool
    database_connected: bool
    embedding_count: int
    antispoofing: str


class RegisterResponse(BaseModel):
    employee_id: int
    employee_name: str | None = None
    frames_received: int
    frames_accepted: int
    embedding_dimension: int
    registered_at: datetime


class MatchEmployee(BaseModel):
    employee_id: int
    employee_name: str | None = None


class MatchResponse(BaseModel):
    matched: bool
    confidence: float = Field(ge=-1.0, le=1.0)
    threshold: float
    timestamp: datetime
    employee: MatchEmployee | None = None
    reason: str | None = None
    second_best_confidence: float | None = Field(default=None, ge=-1.0, le=1.0)


class FaceBox(BaseModel):
    left: float
    top: float
    right: float
    bottom: float


class MultiFaceMatch(BaseModel):
    matched: bool
    confidence: float = Field(ge=-1.0, le=1.0)
    threshold: float
    bbox: FaceBox
    employee: MatchEmployee | None = None
    reason: str | None = None
    second_best_confidence: float | None = Field(default=None, ge=-1.0, le=1.0)


class MultiMatchResponse(BaseModel):
    timestamp: datetime
    image_width: int
    image_height: int
    faces: list[MultiFaceMatch]


class DeleteResponse(BaseModel):
    employee_id: int
    deleted: bool
