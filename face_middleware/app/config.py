from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="FACE_MIDDLEWARE_")

    api_key: str = "change-me"
    embedding_backend: str = Field(default="insightface", pattern="^(insightface|dev)$")
    database_path: str = "./data/face_middleware.sqlite3"
    match_threshold: float = 0.45
    detection_threshold: float = 0.6
    max_file_bytes: int = 5 * 1024 * 1024
    allow_antispoof_stub: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()
