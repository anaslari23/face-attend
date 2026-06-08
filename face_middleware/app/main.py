from datetime import datetime, timezone

import numpy as np
from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile

from .anti_spoofing import AntiSpoofingService
from .config import Settings, get_settings
from .dependencies import get_anti_spoofing_service, get_face_engine, get_repository
from .errors import FacePipelineError, as_http_error
from .face_engine import FaceEngine
from .image_processing import decode_jpeg
from .repository import EmbeddingRepository
from .schemas import DeleteResponse, HealthResponse, MatchEmployee, MatchResponse, RegisterResponse
from .security import require_api_key

app = FastAPI(title="FaceAttend Middleware", version="0.1.0")


@app.get("/health", response_model=HealthResponse)
def health(
    settings: Settings = Depends(get_settings),
    repository: EmbeddingRepository = Depends(get_repository),
    engine: FaceEngine = Depends(get_face_engine),
    anti_spoofing: AntiSpoofingService = Depends(get_anti_spoofing_service),
) -> HealthResponse:
    database_connected = repository.health()
    embedding_count = repository.count() if database_connected else 0
    return HealthResponse(
        status="ok" if engine.model_loaded and database_connected else "degraded",
        embedding_backend=settings.embedding_backend,
        model_loaded=engine.model_loaded,
        database_connected=database_connected,
        embedding_count=embedding_count,
        antispoofing=anti_spoofing.mode,
    )


@app.post("/register", response_model=RegisterResponse, dependencies=[Depends(require_api_key)])
async def register_employee(
    employee_id: int = Form(...),
    employee_name: str | None = Form(default=None),
    files: list[UploadFile] = File(...),
    settings: Settings = Depends(get_settings),
    repository: EmbeddingRepository = Depends(get_repository),
    engine: FaceEngine = Depends(get_face_engine),
    anti_spoofing: AntiSpoofingService = Depends(get_anti_spoofing_service),
) -> RegisterResponse:
    if len(files) < 3:
        raise HTTPException(
            status_code=400,
            detail={"code": "insufficient_frames", "message": "At least 3 enrollment frames are required."},
        )

    embeddings: list[np.ndarray] = []
    for upload in files:
        try:
            image = decode_jpeg(await upload.read(), max_file_bytes=settings.max_file_bytes)
            anti_spoofing.validate(image)
            embeddings.append(engine.embed(image))
        except FacePipelineError as error:
            raise as_http_error(error) from error

    centroid = np.mean(np.stack(embeddings), axis=0)
    norm = float(np.linalg.norm(centroid))
    if norm == 0:
        raise HTTPException(
            status_code=422,
            detail={"code": "empty_centroid", "message": "Enrollment frames produced an empty centroid."},
        )
    centroid = (centroid / norm).astype(np.float32)
    repository.upsert(employee_id=employee_id, employee_name=employee_name, embedding=centroid)

    return RegisterResponse(
        employee_id=employee_id,
        employee_name=employee_name,
        frames_received=len(files),
        frames_accepted=len(embeddings),
        embedding_dimension=int(centroid.shape[0]),
        registered_at=datetime.now(timezone.utc),
    )


@app.post("/match", response_model=MatchResponse, dependencies=[Depends(require_api_key)])
async def match_employee(
    file: UploadFile = File(...),
    settings: Settings = Depends(get_settings),
    repository: EmbeddingRepository = Depends(get_repository),
    engine: FaceEngine = Depends(get_face_engine),
    anti_spoofing: AntiSpoofingService = Depends(get_anti_spoofing_service),
) -> MatchResponse:
    try:
        image = decode_jpeg(await file.read(), max_file_bytes=settings.max_file_bytes)
        anti_spoofing.validate(image)
        query_embedding = engine.embed(image)
    except FacePipelineError as error:
        raise as_http_error(error) from error

    candidates = repository.nearest(query_embedding, limit=1)
    timestamp = datetime.now(timezone.utc)
    if not candidates:
        return MatchResponse(
            matched=False,
            confidence=0.0,
            threshold=settings.match_threshold,
            timestamp=timestamp,
            reason="no_registered_embeddings",
        )
    employee = candidates[0]
    score = employee.score or 0.0
    if score < settings.match_threshold:
        return MatchResponse(
            matched=False,
            confidence=score,
            threshold=settings.match_threshold,
            timestamp=timestamp,
            reason="below_threshold",
        )

    return MatchResponse(
        matched=True,
        confidence=score,
        threshold=settings.match_threshold,
        timestamp=timestamp,
        employee=MatchEmployee(employee_id=employee.employee_id, employee_name=employee.employee_name),
    )


@app.delete("/employee/{employee_id}", response_model=DeleteResponse, dependencies=[Depends(require_api_key)])
def delete_employee(
    employee_id: int,
    repository: EmbeddingRepository = Depends(get_repository),
) -> DeleteResponse:
    return DeleteResponse(employee_id=employee_id, deleted=repository.delete(employee_id))
