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
    ApproveEmbeddingResponse,
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
    antispoof_model_loaded = anti_spoofing.model_loaded
    antispoof_ready = not anti_spoofing.enabled or settings.allow_antispoof_stub or antispoof_model_loaded
    return HealthResponse(
        status="ok" if engine.model_loaded and database_connected and antispoof_ready else "degraded",
        embedding_backend=settings.embedding_backend,
        model_loaded=engine.model_loaded,
        database_connected=database_connected,
        embedding_count=embedding_count,
        antispoofing=anti_spoofing.mode,
        antispoofing_enabled=anti_spoofing.enabled,
        antispoofing_model_loaded=antispoof_model_loaded,
        antispoofing_threshold=anti_spoofing.threshold if anti_spoofing.enabled else None,
    )


def _match_embedding(
    query_embedding: np.ndarray,
    settings: Settings,
    repository: EmbeddingRepository,
) -> tuple[bool, EmployeeEmbedding | None, float, str | None, float | None, EmployeeEmbedding | None, bool]:
    candidates = repository.nearest(query_embedding, limit=10)
    if not candidates:
        return False, None, 0.0, "no_registered_embeddings", None, None, False

    grouped: list[EmployeeEmbedding] = []
    seen_employee_ids: set[int] = set()
    for candidate in candidates:
        if candidate.employee_id in seen_employee_ids:
            continue
        seen_employee_ids.add(candidate.employee_id)
        grouped.append(candidate)

    employee = grouped[0]
    score = employee.score or 0.0
    second_best = grouped[1] if len(grouped) > 1 else None
    second_best_score = second_best.score if second_best else None
    if score < settings.match_threshold:
        needs_review = score >= settings.review_threshold
        reason = "needs_review" if needs_review else "below_threshold"
        return False, employee, score, reason, second_best_score, second_best, needs_review
    if second_best_score is not None and (score - second_best_score) < settings.ambiguity_margin:
        return False, employee, score, "ambiguous_match", second_best_score, second_best, False
    return True, employee, score, None, second_best_score, second_best, False


def _match_employee_payload(employee: EmployeeEmbedding | None) -> MatchEmployee | None:
    if not employee:
        return None
    return MatchEmployee(employee_id=employee.employee_id, employee_name=employee.employee_name)


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
    embedding_id = repository.upsert(employee_id=employee_id, employee_name=employee_name, embedding=centroid)

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
        face_embeddings = engine.embed_many(image)
        if not face_embeddings:
            raise FacePipelineError("no_face_detected", "No face detected.")
        if len(face_embeddings) > 1:
            raise FacePipelineError("multiple_faces_detected", "Multiple faces detected.")
        query_face = face_embeddings[0]
        liveness_score = anti_spoofing.validate(image, query_face.bbox)
        query_embedding = query_face.embedding
    except FacePipelineError as error:
        raise as_http_error(error) from error

    timestamp = datetime.now(timezone.utc)
    matched, employee, score, reason, second_best_score, second_best, needs_review = _match_embedding(
        query_embedding,
        settings,
        repository,
    )
    review_embedding_id = None
    if needs_review and employee:
        review_embedding_id = repository.add_variant(
            employee_id=employee.employee_id,
            employee_name=employee.employee_name,
            embedding=query_embedding,
            source="review_candidate",
            active=False,
            quality_score=score,
        )
    if not matched:
        return MatchResponse(
            matched=False,
            confidence=score,
            threshold=settings.match_threshold,
            review_threshold=settings.review_threshold,
            timestamp=timestamp,
            employee=_match_employee_payload(employee),
            reason=reason,
            second_best_confidence=second_best_score,
            embedding_source=employee.source if employee else None,
            embedding_id=employee.embedding_id if employee else None,
            needs_review=needs_review,
            review_embedding_id=review_embedding_id,
            liveness_passed=liveness_score is not None,
            liveness_score=liveness_score,
            spoof_score=1.0 - liveness_score if liveness_score is not None else None,
        )

    if employee and score >= settings.adaptive_update_threshold:
        repository.add_variant(
            employee_id=employee.employee_id,
            employee_name=employee.employee_name,
            embedding=query_embedding,
            source="adaptive_scan",
            active=True,
            quality_score=score,
            max_active_embeddings=settings.max_employee_embeddings,
        )

    return MatchResponse(
        matched=True,
        confidence=score,
        threshold=settings.match_threshold,
        review_threshold=settings.review_threshold,
        timestamp=timestamp,
        employee=_match_employee_payload(employee),
        second_best_confidence=second_best_score,
        embedding_source=employee.source if employee else None,
        embedding_id=employee.embedding_id if employee else None,
        liveness_passed=liveness_score is not None,
        liveness_score=liveness_score,
        spoof_score=1.0 - liveness_score if liveness_score is not None else None,
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
        face_embeddings = engine.embed_many(image)
    except FacePipelineError as error:
        raise as_http_error(error) from error

    height, width = image.shape[:2]
    faces: list[MultiFaceMatch] = []
    for face in face_embeddings:
        try:
            liveness_score = anti_spoofing.validate(image, face.bbox)
        except FacePipelineError as error:
            raise as_http_error(error) from error
        matched, employee, score, reason, second_best_score, second_best, needs_review = _match_embedding(
            face.embedding,
            settings,
            repository,
        )
        review_embedding_id = None
        if needs_review and employee:
            review_embedding_id = repository.add_variant(
                employee_id=employee.employee_id,
                employee_name=employee.employee_name,
                embedding=face.embedding,
                source="review_candidate",
                active=False,
                quality_score=score,
            )
        left, top, right, bottom = face.bbox
        faces.append(
            MultiFaceMatch(
                matched=matched,
                confidence=score,
                threshold=settings.match_threshold,
                review_threshold=settings.review_threshold,
                bbox=FaceBox(left=left, top=top, right=right, bottom=bottom),
                employee=_match_employee_payload(employee),
                reason=reason,
                second_best_confidence=second_best_score,
                embedding_source=employee.source if employee else None,
                embedding_id=employee.embedding_id if employee else None,
                needs_review=needs_review,
                review_embedding_id=review_embedding_id,
                liveness_passed=liveness_score is not None,
                liveness_score=liveness_score,
                spoof_score=1.0 - liveness_score if liveness_score is not None else None,
            )
        )

    return MultiMatchResponse(timestamp=timestamp, image_width=width, image_height=height, faces=faces)


@app.delete("/employee/{employee_id}", response_model=DeleteResponse, dependencies=[Depends(require_api_key)])
def delete_employee(
    employee_id: int,
    repository: EmbeddingRepository = Depends(get_repository),
) -> DeleteResponse:
    return DeleteResponse(employee_id=employee_id, deleted=repository.delete(employee_id))


@app.post(
    "/employee/{employee_id}/embedding/{embedding_id}/approve",
    response_model=ApproveEmbeddingResponse,
    dependencies=[Depends(require_api_key)],
)
def approve_employee_embedding(
    employee_id: int,
    embedding_id: int,
    settings: Settings = Depends(get_settings),
    repository: EmbeddingRepository = Depends(get_repository),
) -> ApproveEmbeddingResponse:
    approved = repository.approve_variant(
        employee_id=employee_id,
        embedding_id=embedding_id,
        max_active_embeddings=settings.max_employee_embeddings,
    )
    return ApproveEmbeddingResponse(employee_id=employee_id, embedding_id=embedding_id, approved=approved)
