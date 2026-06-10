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
