import hashlib
import io
import os
import struct
import threading
from functools import lru_cache


MODEL_VERSION = "arcface-w600k-r50-align-v3"
_DESTINATION = ((38.2946, 51.6963), (73.5318, 51.5014), (56.0252, 71.7366), (41.5493, 92.3655), (70.7299, 92.2041))
_LOCK = threading.Lock()


def embed_avatar(env, image_bytes):
    import cv2
    import mediapipe as mp
    import numpy as np
    from odoo.exceptions import UserError
    from PIL import Image, ImageOps

    model_path = os.environ.get("FACE_ATTENDANCE_ARCFACE_MODEL") or env["ir.config_parameter"].sudo().get_param("face_attendance.arcface_model_path")
    if not model_path or not os.path.isfile(model_path):
        raise UserError("Set FACE_ATTENDANCE_ARCFACE_MODEL to the w600k_r50.onnx file on the Odoo server.")
    try:
        image = ImageOps.exif_transpose(Image.open(io.BytesIO(image_bytes))).convert("RGB")
    except Exception as error:
        raise UserError("Invalid employee avatar image.") from error
    pixels = np.asarray(image)
    with _LOCK:
        mesh = _face_mesh()
        faces = mesh.process(pixels).multi_face_landmarks or []
        if len(faces) != 1:
            raise UserError("Employee avatar must contain exactly one face.")
        landmarks = faces[0].landmark
        source = np.array(
            [[landmarks[index].x * image.width, landmarks[index].y * image.height] for index in (33, 263, 1, 61, 291)],
            dtype=np.float32,
        )
        span = source.max(axis=0) - source.min(axis=0)
        short_side = min(image.width, image.height)
        if min(span) < 160 or max(span) > short_side * 0.82:
            raise UserError("Employee avatar face size is invalid.")
        aligned = cv2.warpAffine(pixels, _similarity_transform(source, np), (112, 112), flags=cv2.INTER_LINEAR)
        tensor = ((aligned.astype(np.float32) - 127.5) / 127.5).transpose(2, 0, 1)[None, ...]
        session = _session(model_path)
        vector = session.run(None, {session.get_inputs()[0].name: tensor})[0][0].astype(np.float32)
    norm = np.linalg.norm(vector)
    if vector.size != 512 or not np.isfinite(norm) or norm <= 1e-12:
        raise UserError("ArcFace produced an invalid embedding.")
    quality = float(np.clip(0.85 - abs(min(span) / short_side - 0.40), 0.5, 1.0))
    return struct.pack("!512f", *(vector / norm)), quality, hashlib.sha256(image_bytes).hexdigest()


@lru_cache(maxsize=1)
def _face_mesh():
    import mediapipe as mp

    return mp.solutions.face_mesh.FaceMesh(static_image_mode=True, max_num_faces=2, refine_landmarks=False)


@lru_cache(maxsize=1)
def _session(model_path):
    import onnxruntime as ort

    return ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])


def _similarity_transform(source, np):
    destination = np.asarray(_DESTINATION, dtype=np.float32)
    source_center = source.mean(axis=0)
    destination_center = destination.mean(axis=0)
    source_zero = source - source_center
    destination_zero = destination - destination_center
    denominator = np.sum(source_zero * source_zero)
    if denominator <= 1e-6:
        raise ValueError("Invalid face landmarks.")
    a = np.sum(source_zero[:, 0] * destination_zero[:, 0] + source_zero[:, 1] * destination_zero[:, 1]) / denominator
    b = np.sum(source_zero[:, 0] * destination_zero[:, 1] - source_zero[:, 1] * destination_zero[:, 0]) / denominator
    translation = destination_center - np.asarray((a * source_center[0] - b * source_center[1], b * source_center[0] + a * source_center[1]))
    return np.asarray(((a, -b, translation[0]), (b, a, translation[1])), dtype=np.float32)
