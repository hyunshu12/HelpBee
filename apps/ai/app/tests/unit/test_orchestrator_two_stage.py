"""run_analysis two-stage 분기 — 이중 출력(risk_score=score_mapping(vdi), tier_legacy), 폴백, OpenAI shim."""
from io import BytesIO

import numpy as np
from PIL import Image

from app.services.orchestrator import run_analysis
from app.services.risk import score_from_rate
from app.services.two_stage_engine import BeeDet, BudgetExceeded, TwoStageResult
from app.services.vdi import VdiConfig

from .conftest import StubOpenAI

CFG = VdiConfig(tau=0.6, tpr=0.9, fpr=0.01, corrected=True)


class FakeTwoStage:
    model_version = "helpbee-two-stage-test"
    model_versions = {"stage1": "s1-test", "stage2": "s2-test", "vdi_config": "v-test"}

    def __init__(self, bees, error=None):
        self.bees, self.error = bees, error
        self.seen_shape = None

    def analyze(self, image, cfg, *, deadline=None):
        if self.error:
            raise self.error
        self.seen_shape = image.shape
        b = [BeeDet(box=(0, 0, 60, 60), p_infested=p, infested=p > cfg.tau) for p in self.bees]
        return TwoStageResult(bees=b, bee_total=len(b), bee_infested=sum(x.infested for x in b),
                              sampled=False, evidence=[], model_versions=self.model_versions,
                              stage_latency_ms={"stage1": 1, "stage2": 2})


def test_engine_zero_bees_insufficient(jpeg_bytes):
    r = run_analysis(jpeg_bytes, engine="yolo", two_stage=FakeTwoStage([]), vdi_cfg=CFG)
    assert r.tier == "insufficient" and r.vdi is None and r.bee_total == 0 and r.engine_used == "yolo"
    assert r.tier_legacy == "unknown" and r.risk_score is None and r.vdi_display is None
    assert r.recommendations and r.model_versions["stage1"] == "s1-test"


def test_engine_dual_output_risk_score_is_score_mapping(jpeg_bytes):
    r = run_analysis(jpeg_bytes, engine="yolo", two_stage=FakeTwoStage([0.9] * 12 + [0.1] * 88), vdi_cfg=CFG)
    assert r.tier == "high" and r.tier_legacy == "danger"
    assert r.risk_score == score_from_rate(r.vdi)  # 점수 단위 (≈ 77), round(vdi) 아님
    assert r.vdi_display == "12.4" and r.bee_total == 100 and r.bee_infested == 12
    assert r.vdi_raw == 12.0 and r.corrected is True
    lo, hi = r.sampling_ci95
    assert lo < r.vdi < hi
    assert len(r.bees) == 100 and r.bees[0].infested is True
    assert r.quality["ok"] is True and r.raw_payload["sampled"] is False
    assert r.model_version == "helpbee-two-stage-test" and r.fallback_reason is None


def test_two_stage_bypasses_max_edge(jpeg_bytes):
    arr = np.random.default_rng(1).integers(0, 255, (1500, 2000, 3), dtype=np.uint8)
    buf = BytesIO()
    Image.fromarray(arr).save(buf, "JPEG", quality=90)
    eng = FakeTwoStage([0.1] * 40)
    run_analysis(buf.getvalue(), engine="yolo", two_stage=eng, vdi_cfg=CFG)
    assert eng.seen_shape == (1500, 2000, 3)  # 1024 축소 없음


def test_low_tier_recommendations_include_next_check_window(jpeg_bytes):
    r = run_analysis(jpeg_bytes, engine="yolo", two_stage=FakeTwoStage([0.1] * 100), vdi_cfg=CFG)
    assert r.tier == "low" and r.tier_legacy == "safe"
    assert any("점검" in s for s in r.recommendations)


def test_quality_fail_keeps_vdi_but_insufficient():
    buf = BytesIO()
    Image.new("RGB", (640, 480), (20, 20, 20)).save(buf, "JPEG")  # 어둡고 평탄 → 품질 실패
    r = run_analysis(buf.getvalue(), engine="yolo", two_stage=FakeTwoStage([0.9] * 5 + [0.1] * 45), vdi_cfg=CFG)
    assert r.tier == "insufficient" and r.vdi is not None and r.quality["ok"] is False


def test_openai_shim_contract(jpeg_bytes, fake_openai_rate_7):
    r = run_analysis(jpeg_bytes, engine="auto", two_stage=FakeTwoStage([]), openai=fake_openai_rate_7, vdi_cfg=CFG)
    assert r.engine_used == "openai" and r.fallback_reason == "insufficient"
    assert r.vdi_raw == 7.0 and r.corrected is False and r.bee_total is None and r.bees == [] and r.tier == "elevated"
    assert r.vdi == 7.0 and r.vdi_display == "7.0" and r.sampling_ci95 is None and r.bee_infested is None
    assert r.tier_legacy == "watch" and r.model_versions is None  # API 가 two-stage 행을 고르지 않게
    assert r.risk_score == score_from_rate(7.0)


def test_low_count_triggers_paid_fallback(jpeg_bytes):
    oa = StubOpenAI(rate=2.0)
    r = run_analysis(jpeg_bytes, engine="auto", two_stage=FakeTwoStage([0.1] * 20), openai=oa, vdi_cfg=CFG)
    assert oa.called and r.fallback_reason == "low_count" and r.tier == "low"


def test_free_never_falls_back(jpeg_bytes):
    oa = StubOpenAI()
    r = run_analysis(jpeg_bytes, engine="yolo", two_stage=FakeTwoStage([0.1] * 20), openai=oa, vdi_cfg=CFG)
    assert not oa.called and r.engine_used == "yolo" and r.bee_total == 20


def test_enough_bees_no_fallback(jpeg_bytes):
    oa = StubOpenAI()
    r = run_analysis(jpeg_bytes, engine="auto", two_stage=FakeTwoStage([0.1] * 40), openai=oa, vdi_cfg=CFG)
    assert not oa.called and r.engine_used == "yolo"


def test_openai_fallback_failure_returns_two_stage_result(jpeg_bytes):
    r = run_analysis(jpeg_bytes, engine="auto", two_stage=FakeTwoStage([0.1] * 10),
                     openai=StubOpenAI(error=True), vdi_cfg=CFG)
    assert r.engine_used == "yolo" and r.bee_total == 10


def test_engine_error_graceful_or_fallback(jpeg_bytes):
    r = run_analysis(jpeg_bytes, engine="yolo", two_stage=FakeTwoStage([], error=BudgetExceeded("x")), vdi_cfg=CFG)
    assert r.engine_used is None and r.risk_score is None and r.raw_payload["error_reason"]
    oa = StubOpenAI(rate=12.0)
    r2 = run_analysis(jpeg_bytes, engine="auto", two_stage=FakeTwoStage([], error=RuntimeError("boom")),
                      openai=oa, vdi_cfg=CFG)
    assert r2.engine_used == "openai" and r2.fallback_reason == "two_stage_error" and r2.tier == "high"


def test_vdi_cfg_defaults_from_engine(jpeg_bytes):
    class WithCfg(FakeTwoStage):
        def vdi_config(self):
            return CFG

    r = run_analysis(jpeg_bytes, engine="yolo", two_stage=WithCfg([0.9] * 12 + [0.1] * 88))
    assert r.vdi_display == "12.4"
