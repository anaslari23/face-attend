from fastapi import HTTPException, status


class FacePipelineError(Exception):
    def __init__(self, code: str, message: str, status_code: int = status.HTTP_422_UNPROCESSABLE_ENTITY):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code


def as_http_error(error: FacePipelineError) -> HTTPException:
    return HTTPException(
        status_code=error.status_code,
        detail={"code": error.code, "message": error.message},
    )
