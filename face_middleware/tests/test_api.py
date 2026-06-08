import io

import cv2
import numpy as np
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

    def init_storage(self) -> None:
        return None

    def upsert(self, employee_id: int, employee_name: str | None, embedding: np.ndarray) -> None:
        self.records[employee_id] = EmployeeEmbedding(employee_id, employee_name, embedding)

    def delete(self, employee_id: int) -> bool:
        return self.records.pop(employee_id, None) is not None

    def count(self) -> int:
        return len(self.records)

    def health(self) -> bool:
        return True

    def nearest(self, query: np.ndarray, limit: int = 1) -> list[EmployeeEmbedding]:
        scored = []
        for record in self.records.values():
            score = float(np.dot(query, record.embedding) / (np.linalg.norm(query) * np.linalg.norm(record.embedding)))
            scored.append(EmployeeEmbedding(record.employee_id, record.employee_name, record.embedding, score))
        return sorted(scored, key=lambda item: item.score or 0.0, reverse=True)[:limit]


def test_health_and_register_match_delete():
    settings = Settings(
        api_key="test-key",
        embedding_backend="dev",
        database_url="postgresql://test:test@127.0.0.1:5432/test",
        match_threshold=0.45,
    )
    repository = FakeEmbeddingRepository()

    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_repository] = lambda: repository
    app.dependency_overrides[get_face_engine] = lambda: DevFaceEngine()
    app.dependency_overrides[get_anti_spoofing_service] = lambda: AntiSpoofingService(settings)

    client = TestClient(app)

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json()["embedding_backend"] == "dev"
    assert health.json()["database_connected"] is True

    files = [("files", (f"frame{i}.jpg", io.BytesIO(_jpeg(1)), "image/jpeg")) for i in range(3)]
    register = client.post(
        "/register",
        data={"employee_id": "42", "employee_name": "Demo Employee"},
        files=files,
        headers={"X-API-Key": "test-key"},
    )
    assert register.status_code == 200
    assert register.json()["employee_id"] == 42
    assert register.json()["embedding_dimension"] == 512

    match = client.post(
        "/match",
        files={"file": ("scan.jpg", io.BytesIO(_jpeg(1)), "image/jpeg")},
        headers={"X-API-Key": "test-key"},
    )
    assert match.status_code == 200
    assert match.json()["matched"] is True
    assert match.json()["employee"]["employee_id"] == 42

    delete = client.delete("/employee/42", headers={"X-API-Key": "test-key"})
    assert delete.status_code == 200
    assert delete.json()["deleted"] is True

    app.dependency_overrides.clear()


def test_auth_required():
    client = TestClient(app)
    response = client.post("/match")
    assert response.status_code == 401
