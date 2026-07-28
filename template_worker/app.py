import base64
import hashlib
import io
import os
import struct
import threading

import cv2
import mediapipe as mp
import numpy as np
import onnxruntime as ort
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from PIL import Image, ImageOps


MODEL_VERSION = "arcface-w600k-r50-align-v3"
MODEL_PATH = "/models/w600k_r50.onnx"
WORKER_TOKEN = os.environ.get("WORKER_TOKEN")
DESTINATION = np.array(
    [[38.2946, 51.6963], [73.5318, 51.5014], [56.0252, 71.7366], [41.5493, 92.3655], [70.7299, 92.2041]],
    dtype=np.float32,
)


class TemplateRequest(BaseModel):
    employee_id: int
    model_version: str
    avatar_base64: str


class ArcFaceWorker:
    def __init__(self):
        self._mesh = mp.solutions.face_mesh.FaceMesh(
            static_image_mode=True,
            max_num_faces=2,
            refine_landmarks=False,
        )
        self._session = ort.InferenceSession(MODEL_PATH, providers=["CPUExecutionProvider"])
        self._input_name = self._session.get_inputs()[0].name
        self._lock = threading.Lock()

    def embed(self, image_bytes):
        try:
            image = ImageOps.exif_transpose(Image.open(io.BytesIO(image_bytes))).convert("RGB")
        except Exception as error:
            raise ValueError("invalid_avatar_image") from error
        pixels = np.asarray(image)
        with self._lock:
            result = self._mesh.process(pixels)
            faces = result.multi_face_landmarks or []
            if len(faces) != 1:
                raise ValueError("avatar_must_contain_exactly_one_face")
            landmarks = faces[0].landmark
            source = np.array(
                [[landmarks[index].x * image.width, landmarks[index].y * image.height] for index in (33, 263, 1, 61, 291)],
                dtype=np.float32,
            )
            span = source.max(axis=0) - source.min(axis=0)
            short_side = min(image.width, image.height)
            if min(span) < 160 or max(span) > short_side * 0.82:
                raise ValueError("avatar_face_size_invalid")
            matrix = self._similarity_transform(source)
            aligned = cv2.warpAffine(pixels, matrix, (112, 112), flags=cv2.INTER_LINEAR)
            tensor = ((aligned.astype(np.float32) - 127.5) / 127.5).transpose(2, 0, 1)[None, ...]
            vector = self._session.run(None, {self._input_name: tensor})[0][0].astype(np.float32)
        norm = np.linalg.norm(vector)
        if vector.size != 512 or not np.isfinite(norm) or norm <= 1e-12:
            raise ValueError("invalid_arcface_embedding")
        return vector / norm, float(np.clip(0.85 - abs(min(span) / short_side - 0.40), 0.5, 1.0))

    @staticmethod
    def _similarity_transform(source):
        source_center = source.mean(axis=0)
        destination_center = DESTINATION.mean(axis=0)
        source_zero = source - source_center
        destination_zero = DESTINATION - destination_center
        denominator = np.sum(source_zero * source_zero)
        if denominator <= 1e-6:
            raise ValueError("invalid_face_landmarks")
        a = np.sum(source_zero[:, 0] * destination_zero[:, 0] + source_zero[:, 1] * destination_zero[:, 1]) / denominator
        b = np.sum(source_zero[:, 0] * destination_zero[:, 1] - source_zero[:, 1] * destination_zero[:, 0]) / denominator
        translation = destination_center - np.array([a * source_center[0] - b * source_center[1], b * source_center[0] + a * source_center[1]])
        return np.array([[a, -b, translation[0]], [b, a, translation[1]]], dtype=np.float32)


if not WORKER_TOKEN:
    raise RuntimeError("WORKER_TOKEN is required")

worker = ArcFaceWorker()
app = FastAPI(title="Face Attendance Template Worker")


@app.get("/healthz")
def healthz():
    return {"model_version": MODEL_VERSION, "status": "ok"}


@app.post("/v1/templates")
def template(request: TemplateRequest, authorization: str | None = Header(default=None)):
    if authorization != f"Bearer {WORKER_TOKEN}":
        raise HTTPException(status_code=401, detail="unauthorized")
    if request.model_version != MODEL_VERSION:
        raise HTTPException(status_code=422, detail="unsupported_model_version")
    try:
        image_bytes = base64.b64decode(request.avatar_base64, validate=True)
        vector, quality_score = worker.embed(image_bytes)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    return {
        "employee_id": request.employee_id,
        "model_version": MODEL_VERSION,
        "avatar_hash": hashlib.sha256(image_bytes).hexdigest(),
        "embedding_b64": base64.b64encode(struct.pack("!512f", *vector)).decode(),
        "quality_score": quality_score,
    }
