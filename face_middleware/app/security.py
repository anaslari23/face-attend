from fastapi import Depends, Header, HTTPException, status

from .config import Settings, get_settings


def require_api_key(
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
    authorization: str | None = Header(default=None, alias="Authorization"),
    settings: Settings = Depends(get_settings),
) -> None:
    bearer = None
    if authorization and authorization.lower().startswith("bearer "):
        bearer = authorization[7:].strip()

    supplied = x_api_key or bearer
    if supplied != settings.api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_api_key", "message": "A valid API key is required."},
        )
