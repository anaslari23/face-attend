import io

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.anti_spoofing import AntiSpoofingService
from app.config import Settings, get_settings
from app.dependencies import get_anti_spoofing_service, get_face_engine, get_repository
from app.face_engine import DevFaceEngine
from app.main import app
from app.repository import EmployeeEmbedding


def _jpeg(seed: int) -> bytes:
    rng = np.random.default_rng(seed)
    image = rng.integers(0, 255, size=(240, 240, 3), dtype=np.uint8)
    ok, encoded = cv2.imencode(".jpg", image)
    assert ok
    return encoded.tobytes()


class FakeEmbeddingRepository:
    def __init__(self):
        self.records = {}
        self.next_id = 1

    def init_storage(self) -> None:
        return None

    def upsert(self, employee_id: int, employee_name: str | None, embedding: np.ndarray) -> int:
        embedding_id = self.next_id
        self.next_id += 1
        self.records[embedding_id] = EmployeeEmbedding(
            embedding_id,
            employee_id,
            employee_name,
            embedding,
            source="avatar_primary",
        )
        return embedding_id

    def add_variant(
        self,
        employee_id: int,
        employee_name: str | None,
        embedding: np.ndarray,
        source: str,
        active: bool,
        quality_score: float | None = None,
        max_active_embeddings: int | None = None,
    ) -> int:
        embedding_id = self.next_id
        self.next_id += 1
        self.records[embedding_id] = EmployeeEmbedding(
            embedding_id,
            employee_id,
            employee_name,
            embedding,
            source=source,
            active=active,
        )
        return embedding_id

    def approve_variant(self, employee_id: int, embedding_id: int, max_active_embeddings: int | None = None) -> bool:
        record = self.records.get(embedding_id)
        if not record or record.employee_id != employee_id or record.active or record.source != "review_candidate":
            return False
        self.records[embedding_id] = EmployeeEmbedding(
            record.embedding_id,
            record.employee_id,
            record.employee_name,
            record.embedding,
            source="adaptive_scan",
            active=True,
        )
        return True

    def delete(self, employee_id: int) -> bool:
        deleted = False
        for embedding_id, record in list(self.records.items()):
            if record.employee_id == employee_id:
                self.records.pop(embedding_id)
                deleted = True
        return deleted

    def count(self) -> int:
        return len([record for record in self.records.values() if record.active])

    def health(self) -> bool:
        return True

    def nearest(self, query: np.ndarray, limit: int = 1) -> list[EmployeeEmbedding]:
        scored = []
        for record in self.records.values():
            if not record.active:
                continue
            score = float(np.dot(query, record.embedding) / (np.linalg.norm(query) * np.linalg.norm(record.embedding)))
            scored.append(
                EmployeeEmbedding(
                    record.embedding_id,
                    record.employee_id,
                    record.employee_name,
                    record.embedding,
                    source=record.source,
                    score=score,
                )
            )
        return sorted(scored, key=lambda item: item.score or 0.0, reverse=True)[:limit]


class AllowAntiSpoofingService:
    mode = "test"
    enabled = True
    model_loaded = True
    threshold = 0.80

    def validate(self, image: np.ndarray, bbox=None) -> float:
        return 1.0


def test_health_and_register_match_delete():
    settings = Settings(
        api_key="test-key",
        embedding_backend="dev",
        database_url="postgresql://test:test@127.0.0.1:5432/test",
        match_threshold=0.70,
    )
    repository = FakeEmbeddingRepository()

    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_repository] = lambda: repository
    app.dependency_overrides[get_face_engine] = lambda: DevFaceEngine()
    app.dependency_overrides[get_anti_spoofing_service] = lambda: AllowAntiSpoofingService()

    client = TestClient(app)

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json()["embedding_backend"] == "dev"
    assert health.json()["database_connected"] is True

    register = client.post(
        "/register",
        data={"employee_id": "42", "employee_name": "Demo Employee"},
        files={"files": ("face.jpg", io.BytesIO(_jpeg(1)), "image/jpeg")},
        headers={"X-API-Key": "test-key"},
    )
    assert register.status_code == 200
    assert register.json()["employee_id"] == 42
    assert register.json()["embedding_dimension"] == 512
    assert register.json()["detection_score"] == 1.0
    assert register.json()["face_ratio"] == 1.0
    assert register.json()["blur_variance"] == 100.0
    assert register.json()["face_box"]["right"] == 240.0

    match = client.post(
        "/match",
        files={"file": ("scan.jpg", io.BytesIO(_jpeg(1)), "image/jpeg")},
        headers={"X-API-Key": "test-key"},
    )
    assert match.status_code == 200
    assert match.json()["matched"] is True
    assert match.json()["employee"]["employee_id"] == 42
    assert match.json()["threshold"] == 0.70

    delete = client.delete("/employee/42", headers={"X-API-Key": "test-key"})
    assert delete.status_code == 200
    assert delete.json()["deleted"] is True

    app.dependency_overrides.clear()


def test_ambiguous_match_rejected():
    settings = Settings(
        api_key="test-key",
        embedding_backend="dev",
        database_url="postgresql://test:test@127.0.0.1:5432/test",
        match_threshold=0.70,
        ambiguity_margin=0.08,
    )
    repository = FakeEmbeddingRepository()
    query = np.zeros(512, dtype=np.float32)
    query[0] = 1.0
    second = np.zeros(512, dtype=np.float32)
    second[0] = 0.997
    second[1] = 0.077
    repository.records[1] = EmployeeEmbedding(1, 1, "Best", query)
    repository.records[2] = EmployeeEmbedding(2, 2, "Close", second)

    class FixedFaceEngine(DevFaceEngine):
        def embed(self, image: np.ndarray) -> np.ndarray:
            return query

    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_repository] = lambda: repository
    app.dependency_overrides[get_face_engine] = lambda: FixedFaceEngine()
    app.dependency_overrides[get_anti_spoofing_service] = lambda: AllowAntiSpoofingService()

    client = TestClient(app)
    match = client.post(
        "/match",
        files={"file": ("scan.jpg", io.BytesIO(_jpeg(2)), "image/jpeg")},
        headers={"X-API-Key": "test-key"},
    )
    assert match.status_code == 200
    payload = match.json()
    assert payload["matched"] is False
    assert payload["employee"]["employee_id"] == 1
    assert payload["reason"] == "ambiguous_match"
    assert payload["second_best_confidence"] is not None

    app.dependency_overrides.clear()


def test_below_threshold_returns_nearest_employee_for_diagnostics():
    settings = Settings(
        api_key="test-key",
        embedding_backend="dev",
        database_url="postgresql://test:test@127.0.0.1:5432/test",
        match_threshold=0.95,
        review_threshold=0.85,
        ambiguity_margin=0.01,
    )
    repository = FakeEmbeddingRepository()
    stored = np.zeros(512, dtype=np.float32)
    stored[0] = 1.0
    query = np.zeros(512, dtype=np.float32)
    query[0] = 0.8
    query[1] = 0.6
    repository.records[10] = EmployeeEmbedding(10, 10, "Nearest", stored)

    class FixedFaceEngine(DevFaceEngine):
        def embed(self, image: np.ndarray) -> np.ndarray:
            return query

    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_repository] = lambda: repository
    app.dependency_overrides[get_face_engine] = lambda: FixedFaceEngine()
    app.dependency_overrides[get_anti_spoofing_service] = lambda: AllowAntiSpoofingService()

    client = TestClient(app)
    match = client.post(
        "/match",
        files={"file": ("scan.jpg", io.BytesIO(_jpeg(2)), "image/jpeg")},
        headers={"X-API-Key": "test-key"},
    )
    assert match.status_code == 200
    payload = match.json()
    assert payload["matched"] is False
    assert payload["reason"] == "below_threshold"
    assert payload["employee"]["employee_id"] == 10
    assert payload["confidence"] == pytest.approx(0.8)

    app.dependency_overrides.clear()


def test_review_band_creates_review_candidate_and_can_approve():
    settings = Settings(
        api_key="test-key",
        embedding_backend="dev",
        database_url="postgresql://test:test@127.0.0.1:5432/test",
        match_threshold=0.90,
        review_threshold=0.60,
        ambiguity_margin=0.01,
    )
    repository = FakeEmbeddingRepository()
    stored = np.zeros(512, dtype=np.float32)
    stored[0] = 1.0
    query = np.zeros(512, dtype=np.float32)
    query[0] = 0.8
    query[1] = 0.6
    repository.records[10] = EmployeeEmbedding(10, 10, "Nearest", stored)

    class FixedFaceEngine(DevFaceEngine):
        def embed(self, image: np.ndarray) -> np.ndarray:
            return query

    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_repository] = lambda: repository
    app.dependency_overrides[get_face_engine] = lambda: FixedFaceEngine()
    app.dependency_overrides[get_anti_spoofing_service] = lambda: AllowAntiSpoofingService()

    client = TestClient(app)
    match = client.post(
        "/match",
        files={"file": ("scan.jpg", io.BytesIO(_jpeg(2)), "image/jpeg")},
        headers={"X-API-Key": "test-key"},
    )
    assert match.status_code == 200
    payload = match.json()
    assert payload["matched"] is False
    assert payload["reason"] == "needs_review"
    assert payload["needs_review"] is True
    assert payload["review_embedding_id"] is not None

    approve = client.post(
        f"/employee/10/embedding/{payload['review_embedding_id']}/approve",
        headers={"X-API-Key": "test-key"},
    )
    assert approve.status_code == 200
    assert approve.json()["approved"] is True

    app.dependency_overrides.clear()


def test_match_faces_returns_box_and_employee():
    settings = Settings(
        api_key="test-key",
        embedding_backend="dev",
        database_url="postgresql://test:test@127.0.0.1:5432/test",
        match_threshold=0.70,
    )
    repository = FakeEmbeddingRepository()

    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_repository] = lambda: repository
    app.dependency_overrides[get_face_engine] = lambda: DevFaceEngine()
    app.dependency_overrides[get_anti_spoofing_service] = lambda: AllowAntiSpoofingService()

    client = TestClient(app)
    register = client.post(
        "/register",
        data={"employee_id": "42", "employee_name": "Demo Employee"},
        files={"files": ("face.jpg", io.BytesIO(_jpeg(1)), "image/jpeg")},
        headers={"X-API-Key": "test-key"},
    )
    assert register.status_code == 200

    match = client.post(
        "/match/faces",
        files={"file": ("scan.jpg", io.BytesIO(_jpeg(1)), "image/jpeg")},
        headers={"X-API-Key": "test-key"},
    )
    assert match.status_code == 200
    payload = match.json()
    assert payload["image_width"] == 240
    assert payload["image_height"] == 240
    assert len(payload["faces"]) == 1
    assert payload["faces"][0]["matched"] is True
    assert payload["faces"][0]["employee"]["employee_id"] == 42
    assert payload["faces"][0]["bbox"]["right"] == 240.0

    app.dependency_overrides.clear()


def test_anti_spoofing_required_blocks_match_but_not_register():
    settings = Settings(
        api_key="test-key",
        embedding_backend="dev",
        database_url="postgresql://test:test@127.0.0.1:5432/test",
        match_threshold=0.70,
        anti_spoofing_enabled=True,
        allow_antispoof_stub=False,
        antispoof_model_path="/tmp/face-attend-missing-antispoof.onnx",
    )
    repository = FakeEmbeddingRepository()

    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_repository] = lambda: repository
    app.dependency_overrides[get_face_engine] = lambda: DevFaceEngine()
    app.dependency_overrides[get_anti_spoofing_service] = lambda: AntiSpoofingService(settings)

    client = TestClient(app)
    register = client.post(
        "/register",
        data={"employee_id": "42", "employee_name": "Demo Employee"},
        files={"files": ("face.jpg", io.BytesIO(_jpeg(1)), "image/jpeg")},
        headers={"X-API-Key": "test-key"},
    )
    assert register.status_code == 200

    match = client.post(
        "/match",
        files={"file": ("scan.jpg", io.BytesIO(_jpeg(1)), "image/jpeg")},
        headers={"X-API-Key": "test-key"},
    )
    assert match.status_code == 503
    assert match.json()["detail"]["code"] == "anti_spoofing_unavailable"

    app.dependency_overrides.clear()


def test_auth_required():
    client = TestClient(app)
    response = client.post("/match")
    assert response.status_code == 401
