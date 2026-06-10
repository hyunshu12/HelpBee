"""B5 orchestrator.run_analysis — engine=auto YOLO→OpenAI 폴백.

근거: backend-design §3. FakeYolo/FakeOpenAI 주입으로 4 시나리오 검증:
정상(YOLO) / 폴백(저신뢰→OpenAI) / 무료(폴백 금지) / 양쪽 실패(graceful).
"""

from io import BytesIO

from PIL import Image

from app.services.orchestrator import run_analysis
from app.services.openai_client import OpenAIResult
from app.services.yolo_engine import YoloResult


def _jpeg() -> bytes:
    buf = BytesIO()
    Image.new("RGB", (640, 480), "green").save(buf, "JPEG")
    return buf.getvalue()


class FakeYolo:
    model_version = "helpbee-yolov11s-0.1.0"

    def __init__(self, counts, confidence=0.8, error=False):
        self._counts = counts
        self._conf = confidence
        self._error = error

    def detect(self, jpeg):
        if self._error:
            raise RuntimeError("onnx boom")
        return YoloResult(
            class_counts=self._counts, confidence=self._conf, model_version=self.model_version
        )


class FakeOpenAI:
    def __init__(self, rate=12.0, confidence=0.9, error=False):
        self._rate = rate
        self._conf = confidence
        self._error = error
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


def test_normal_yolo_no_fallback():
    # 충분한 벌, 경계서 먼 1% → 폴백 불필요
    yolo = FakeYolo({0: 98, 1: 1, 2: 1})  # 100마리, 1%
    openai = FakeOpenAI()
    r = run_analysis(_jpeg(), engine="auto", yolo=yolo, openai=openai)
    assert r.engine_used == "yolo"
    assert r.tier == "safe"
    assert r.fallback_reason is None
    assert openai.called is False
    assert r.cost_estimate_usd is None


def test_low_confidence_triggers_openai_fallback():
    # 벌 3마리(<5) → low_confidence → 유료(auto) 폴백
    yolo = FakeYolo({0: 2, 1: 1, 2: 0})
    openai = FakeOpenAI(rate=12.0, confidence=0.9)  # 12% → danger
    r = run_analysis(_jpeg(), engine="auto", yolo=yolo, openai=openai)
    assert openai.called is True
    assert r.engine_used == "openai"
    assert r.fallback_reason == "low_confidence"
    assert r.tier == "danger"
    assert r.cost_estimate_usd and r.cost_estimate_usd > 0
    assert r.raw_payload["fallback_from"]["yolo_bee_total"] == 3


def test_boundary_triggers_fallback():
    # 정확히 10%(watch_max 경계) → 밴드 내 → 폴백
    yolo = FakeYolo({0: 90, 1: 10, 2: 0})
    openai = FakeOpenAI(rate=2.0, confidence=0.9)
    r = run_analysis(_jpeg(), engine="auto", yolo=yolo, openai=openai)
    assert r.engine_used == "openai"
    assert r.fallback_reason == "boundary"


def test_free_engine_never_falls_back():
    # 무료(engine="yolo") → 저신뢰여도 폴백 금지, YOLO 결과 반환
    yolo = FakeYolo({0: 2, 1: 1, 2: 0})
    openai = FakeOpenAI()
    r = run_analysis(_jpeg(), engine="yolo", yolo=yolo, openai=openai)
    assert r.engine_used == "yolo"
    assert openai.called is False
    assert any("신뢰도" in x for x in r.recommendations)  # low_confidence 안내


def test_both_engines_fail_graceful():
    yolo = FakeYolo({}, error=True)
    openai = FakeOpenAI(error=True)
    r = run_analysis(_jpeg(), engine="auto", yolo=yolo, openai=openai)
    assert r.risk_score is None
    assert r.tier == "watch"
    assert r.engine_used is None
    assert r.recommendations  # graceful 안내


def test_yolo_error_paid_falls_back_to_openai():
    yolo = FakeYolo({}, error=True)
    openai = FakeOpenAI(rate=5.0, confidence=0.8)
    r = run_analysis(_jpeg(), engine="auto", yolo=yolo, openai=openai)
    assert r.engine_used == "openai"
    assert r.fallback_reason == "yolo_error"
    assert r.tier == "watch"  # 5% → watch
