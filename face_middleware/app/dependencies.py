from functools import lru_cache

from .config import get_settings
from .face_engine import FaceEngine, build_face_engine
from .repository import EmbeddingRepository


@lru_cache
def get_repository() -> EmbeddingRepository:
    return EmbeddingRepository(get_settings().database_path)


@lru_cache
def get_face_engine() -> FaceEngine:
    return build_face_engine(get_settings())
