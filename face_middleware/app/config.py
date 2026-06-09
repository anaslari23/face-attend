from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="FACE_MIDDLEWARE_")

    api_key: str = "change-me"
    embedding_backend: str = Field(default="insightface", pattern="^(insightface|dev)$")
    database_url: str = "postgresql://face_attend:face_attend@127.0.0.1:5432/face_attend"
    match_threshold: float = 0.70
    ambiguity_margin: float = 0.08
    detection_threshold: float = 0.6
    min_face_ratio: float = 0.18
    max_face_ratio: float = 0.82
    min_blur_variance: float = 35.0
    max_file_bytes: int = 5 * 1024 * 1024
    anti_spoofing_enabled: bool = False
    allow_antispoof_stub: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()
