"""unit 공용 fixture — 품질 체크를 통과하는 질감 있는 JPEG, rate 7% OpenAI 스텁."""
from io import BytesIO

import numpy as np
import pytest
from PIL import Image

from app.services.openai_client import OpenAIResult


@pytest.fixture
def jpeg_bytes() -> bytes:
    arr = np.random.default_rng(0).integers(0, 255, (480, 640, 3), dtype=np.uint8)  # 블러·노출 통과
    buf = BytesIO()
    Image.fromarray(arr).save(buf, "JPEG", quality=95)
    return buf.getvalue()


class StubOpenAI:
    def __init__(self, rate=7.0, confidence=0.9, error=False):
        self._rate, self._conf, self._error = rate, confidence, error
        self.called = False

    def analyze(self, jpeg):
        self.called = True
        if self._error:
            raise RuntimeError("openai down")
        return OpenAIResult(
            infestation_rate=self._rate,
            confidence=self._conf,
            cost_usd=0.0011,
            model_version="gpt-4o-mini-2024-07-18",
            prompt_version="varroa@1.0",
        )


@pytest.fixture
def fake_openai_rate_7() -> StubOpenAI:
    return StubOpenAI(rate=7.0, confidence=0.9)
