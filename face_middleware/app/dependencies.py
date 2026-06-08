from functools import lru_cache

from .anti_spoofing import AntiSpoofingService
from .config import get_settings
from .face_engine import FaceEngine, build_face_engine
from .repository import EmbeddingRepository, PgVectorEmbeddingRepository


@lru_cache
def get_repository() -> EmbeddingRepository:
    return PgVectorEmbeddingRepository(get_settings().database_url)


@lru_cache
def get_face_engine() -> FaceEngine:
    return build_face_engine(get_settings())


@lru_cache
def get_anti_spoofing_service() -> AntiSpoofingService:
    return AntiSpoofingService(get_settings())
