from datetime import datetime, timezone

import numpy as np
from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile

from .anti_spoofing import AntiSpoofingService
from .config import Settings, get_settings
from .dependencies import get_anti_spoofing_service, get_face_engine, get_repository
from .errors import FacePipelineError, as_http_error
from .face_engine import FaceEngine
from .image_processing import decode_jpeg
from .repository import EmbeddingRepository, EmployeeEmbedding
from .schemas import (
    DeleteResponse,
    FaceBox,
    HealthResponse,
    MatchEmployee,
    MatchResponse,
    MultiFaceMatch,
    MultiMatchResponse,
    RegisterResponse,
)
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


def _match_embedding(
    query_embedding: np.ndarray,
    settings: Settings,
    repository: EmbeddingRepository,
) -> tuple[bool, EmployeeEmbedding | None, float, str | None, float | None]:
    candidates = repository.nearest(query_embedding, limit=2)
    if not candidates:
        return False, None, 0.0, "no_registered_embeddings", None

    employee = candidates[0]
    score = employee.score or 0.0
    second_best_score = candidates[1].score if len(candidates) > 1 else None
    if score < settings.match_threshold:
        return False, employee, score, "below_threshold", second_best_score
    if second_best_score is not None and (score - second_best_score) < settings.ambiguity_margin:
        return False, employee, score, "ambiguous_match", second_best_score
    return True, employee, score, None, second_best_score


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
    if len(files) < 1:
        raise HTTPException(
            status_code=400,
            detail={"code": "insufficient_frames", "message": "At least 1 enrollment image is required."},
        )

    embeddings: list[np.ndarray] = []
    registration_faces = []
    for upload in files:
        try:
            image = decode_jpeg(await upload.read(), max_file_bytes=settings.max_file_bytes)
            anti_spoofing.validate(image)
            registration_face = engine.embed_for_registration(image)
            registration_faces.append(registration_face)
            embeddings.append(registration_face.embedding)
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

    primary_face = registration_faces[0] if registration_faces else None
    if primary_face:
        left, top, right, bottom = primary_face.bbox
        face_box = FaceBox(left=left, top=top, right=right, bottom=bottom)
    else:
        face_box = None

    return RegisterResponse(
        employee_id=employee_id,
        employee_name=employee_name,
        frames_received=len(files),
        frames_accepted=len(embeddings),
        embedding_dimension=int(centroid.shape[0]),
        registered_at=datetime.now(timezone.utc),
        detection_score=primary_face.det_score if primary_face else None,
        face_box=face_box,
        face_ratio=primary_face.face_ratio if primary_face else None,
        blur_variance=primary_face.blur_variance if primary_face else None,
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

    timestamp = datetime.now(timezone.utc)
    matched, employee, score, reason, second_best_score = _match_embedding(query_embedding, settings, repository)
    if not matched:
        return MatchResponse(
            matched=False,
            confidence=score,
            threshold=settings.match_threshold,
            timestamp=timestamp,
            employee=MatchEmployee(employee_id=employee.employee_id, employee_name=employee.employee_name)
            if employee
            else None,
            reason=reason,
            second_best_confidence=second_best_score,
        )

    return MatchResponse(
        matched=True,
        confidence=score,
        threshold=settings.match_threshold,
        timestamp=timestamp,
        employee=MatchEmployee(employee_id=employee.employee_id, employee_name=employee.employee_name) if employee else None,
        second_best_confidence=second_best_score,
    )


@app.post("/match/faces", response_model=MultiMatchResponse, dependencies=[Depends(require_api_key)])
async def match_faces(
    file: UploadFile = File(...),
    settings: Settings = Depends(get_settings),
    repository: EmbeddingRepository = Depends(get_repository),
    engine: FaceEngine = Depends(get_face_engine),
    anti_spoofing: AntiSpoofingService = Depends(get_anti_spoofing_service),
) -> MultiMatchResponse:
    timestamp = datetime.now(timezone.utc)
    try:
        image = decode_jpeg(await file.read(), max_file_bytes=settings.max_file_bytes)
        anti_spoofing.validate(image)
        face_embeddings = engine.embed_many(image)
    except FacePipelineError as error:
        raise as_http_error(error) from error

    height, width = image.shape[:2]
    faces: list[MultiFaceMatch] = []
    for face in face_embeddings:
        matched, employee, score, reason, second_best_score = _match_embedding(face.embedding, settings, repository)
        left, top, right, bottom = face.bbox
        faces.append(
            MultiFaceMatch(
                matched=matched,
                confidence=score,
                threshold=settings.match_threshold,
                bbox=FaceBox(left=left, top=top, right=right, bottom=bottom),
                employee=MatchEmployee(employee_id=employee.employee_id, employee_name=employee.employee_name)
                if matched and employee
                else None,
                reason=reason,
                second_best_confidence=second_best_score,
            )
        )

    return MultiMatchResponse(timestamp=timestamp, image_width=width, image_height=height, faces=faces)


@app.delete("/employee/{employee_id}", response_model=DeleteResponse, dependencies=[Depends(require_api_key)])
def delete_employee(
    employee_id: int,
    repository: EmbeddingRepository = Depends(get_repository),
) -> DeleteResponse:
    return DeleteResponse(employee_id=employee_id, deleted=repository.delete(employee_id))
