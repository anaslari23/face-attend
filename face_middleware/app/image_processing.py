import cv2
import numpy as np

from .errors import FacePipelineError


def decode_jpeg(contents: bytes, *, max_file_bytes: int) -> np.ndarray:
    if not contents:
        raise FacePipelineError("empty_image", "Uploaded image is empty.")
    if len(contents) > max_file_bytes:
        raise FacePipelineError("image_too_large", "Uploaded image exceeds the configured size limit.", 413)

    buffer = np.frombuffer(contents, dtype=np.uint8)
    image = cv2.imdecode(buffer, cv2.IMREAD_COLOR)
    if image is None:
        raise FacePipelineError("invalid_image", "Uploaded file is not a valid image.")
    if image.shape[0] < 200 or image.shape[1] < 200:
        raise FacePipelineError("image_too_small", "Image must be at least 200x200 pixels.")
    return image


def apply_clahe(image: np.ndarray) -> np.ndarray:
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    enhanced_l = clahe.apply(l_channel)
    enhanced = cv2.merge((enhanced_l, a_channel, b_channel))
    return cv2.cvtColor(enhanced, cv2.COLOR_LAB2BGR)
