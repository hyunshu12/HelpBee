"""B1 schemas/analysis.py — AnalysisResponse (Pydantic v2).

설계 근거: backend-design §6, apps/ai/CLAUDE.md §6 (응답 스키마),
§3.7 graceful 실패(risk=null, tier=watch).
"""

import pytest
from pydantic import ValidationError

from app.schemas.analysis import AnalysisResponse


def _full(**over):
    base = dict(
        risk_score=42,
        tier="watch",
        estimated_count=None,
        confidence=0.8,
        recommendations=["a", "b"],
        model_version="helpbee-yolov11s-0.1.0",
        prompt_version=None,
        latency_ms=263,
        cost_estimate_usd=None,
        raw_payload={"x": 1},
        engine_used="yolo",
        fallback_reason=None,
    )
    base.update(over)
    return base


def test_roundtrip():
    r = AnalysisResponse(**_full())
    assert AnalysisResponse.model_validate(r.model_dump()) == r


def test_tier_literal_rejects_invalid():
    with pytest.raises(ValidationError):
        AnalysisResponse(**_full(tier="critical"))  # 4분법 폐기, 3분법만


def test_risk_score_clamped():
    assert AnalysisResponse(**_full(risk_score=150)).risk_score == 100
    assert AnalysisResponse(**_full(risk_score=-5)).risk_score == 0


def test_risk_score_nullable():
    assert AnalysisResponse(**_full(risk_score=None)).risk_score is None


def test_confidence_clamped():
    assert AnalysisResponse(**_full(confidence=1.5)).confidence == 1.0
    assert AnalysisResponse(**_full(confidence=-0.2)).confidence == 0.0


def test_engine_used_literal():
    with pytest.raises(ValidationError):
        AnalysisResponse(**_full(engine_used="banana"))
    assert AnalysisResponse(**_full(engine_used=None)).engine_used is None


def test_graceful_failure():
    r = AnalysisResponse.graceful_failure(model_version="m", reason="timeout")
    assert r.risk_score is None
    assert r.tier == "watch"
    assert r.engine_used is None
    assert r.recommendations  # 비어있지 않음
    assert r.raw_payload["error_reason"] == "timeout"


# ── two-stage 계약 (스펙 v2.2 §3) — 새 필드 전부 optional, 이중 출력 ──
def test_two_stage_tiers_accepted_and_new_fields_default():
    for t in ("low", "elevated", "high", "insufficient"):
        r = AnalysisResponse(**_full(tier=t))
        assert r.tier == t
    r = AnalysisResponse(**_full())
    assert r.vdi is None and r.vdi_display is None and r.bee_total is None
    assert r.bees == [] and r.evidence == [] and r.quality is None and r.model_versions is None
    assert r.tier_legacy is None and r.corrected is None and r.sampling_ci95 is None


def test_two_stage_fields_roundtrip():
    r = AnalysisResponse(
        **_full(
            tier="high",
            tier_legacy="danger",
            vdi=12.36,
            vdi_display="12.4",
            vdi_raw=12.0,
            corrected=True,
            sampling_ci95=(6.1, 20.3),
            bee_total=100,
            bee_infested=12,
            bees=[{"box": (0, 0, 10, 10), "p_infested": 0.9, "infested": True}],
            evidence=[{"index": 0, "p_infested": 0.9, "box": (0, 0, 10, 10), "cam": [[0.0]]}],
            quality={"ok": True, "blur_score": 300.0, "exposure_mean": 120.0, "px_per_mm_est": None},
            model_versions={"stage1": "a", "stage2": "b", "vdi_config": "c"},
        )
    )
    d = r.model_dump()
    assert d["bees"][0]["infested"] is True and d["sampling_ci95"] == (6.1, 20.3)
    assert d["model_versions"]["vdi_config"] == "c"


def test_tier_legacy_literal():
    assert AnalysisResponse(**_full(tier_legacy="unknown")).tier_legacy == "unknown"
    with pytest.raises(ValidationError):
        AnalysisResponse(**_full(tier_legacy="low"))
