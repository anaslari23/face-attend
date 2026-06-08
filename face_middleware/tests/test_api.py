import io

import cv2
import numpy as np
from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from app.dependencies import get_face_engine, get_repository
from app.face_engine import DevFaceEngine
from app.main import app
from app.repository import EmbeddingRepository


def _jpeg(seed: int) -> bytes:
    rng = np.random.default_rng(seed)
    image = rng.integers(0, 255, size=(240, 240, 3), dtype=np.uint8)
    ok, encoded = cv2.imencode(".jpg", image)
    assert ok
    return encoded.tobytes()


def test_health_and_register_match_delete(tmp_path):
    settings = Settings(
        api_key="test-key",
        embedding_backend="dev",
        database_path=str(tmp_path / "middleware.sqlite3"),
        match_threshold=0.45,
    )

    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_repository] = lambda: EmbeddingRepository(settings.database_path)
    app.dependency_overrides[get_face_engine] = lambda: DevFaceEngine()

    client = TestClient(app)

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json()["embedding_backend"] == "dev"

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
