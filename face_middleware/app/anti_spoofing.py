import numpy as np

from .config import Settings
from .errors import FacePipelineError


class AntiSpoofingService:
    def __init__(self, settings: Settings):
        self.settings = settings

    @property
    def mode(self) -> str:
        if self.settings.anti_spoofing_enabled:
            return "stub" if self.settings.allow_antispoof_stub else "required"
        return "disabled"

    def validate(self, image: np.ndarray) -> None:
        if not self.settings.anti_spoofing_enabled:
            return
        if self.settings.allow_antispoof_stub:
            return
        raise FacePipelineError(
            "anti_spoofing_unavailable",
            "Anti-spoofing is required but no production anti-spoofing model is configured.",
            503,
        )
