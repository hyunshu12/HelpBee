"""B2 risk.py — infestation_rate → risk_score/tier/recommendations.

근거: apps/ai/training/configs/risk.yaml, AIHUB_71667.md(Q3=B, infestation_rate).
클래스 id: 0=bee_normal, 1=bee_with_varroa, 2=bee_other_disease.
"""

from app.services.risk import compute_risk, RiskResult, tier_from_score


def counts(normal: int = 0, varroa: int = 0, other: int = 0) -> dict[int, int]:
    return {0: normal, 1: varroa, 2: other}


def test_returns_riskresult():
    assert isinstance(compute_risk(counts(normal=10)), RiskResult)


def test_safe_low_rate():
    r = compute_risk(counts(normal=99, varroa=1, other=0))  # 100마리, 1%
    assert r.bee_total == 100
    assert abs(r.infestation_rate - 1.0) < 1e-6
    assert r.tier == "safe"
    assert r.risk_score == 7  # 1% * 7
    assert r.low_confidence is False
    assert any("안전" in x for x in r.recommendations)


def test_watch_mid_rate():
    r = compute_risk(counts(normal=90, varroa=5, other=5))  # 5%
    assert r.tier == "watch"
    assert r.risk_score == 35


def test_danger_high_rate():
    r = compute_risk(counts(normal=80, varroa=15, other=5))  # 15%
    assert r.tier == "danger"
    assert r.risk_score == 85  # 70 + (15-10)*3


def test_boundary_three_percent_is_watch():
    r = compute_risk(counts(normal=97, varroa=3, other=0))  # 정확히 3.0%
    assert r.tier == "watch"
    assert r.risk_score == 21


def test_boundary_ten_percent_is_watch():
    r = compute_risk(counts(normal=90, varroa=10, other=0))  # 정확히 10%
    assert r.tier == "watch"
    assert r.risk_score == 70


def test_above_ten_is_danger():
    r = compute_risk(counts(normal=88, varroa=12, other=0))  # 12%
    assert r.tier == "danger"
    assert r.risk_score == 76  # 70 + 2*3


def test_saturation_clamped_to_100():
    r = compute_risk(counts(normal=75, varroa=25, other=0))  # 25%
    assert r.risk_score == 100
    assert r.tier == "danger"


def test_low_confidence_few_bees_forces_watch():
    r = compute_risk(counts(normal=2, varroa=1, other=0))  # 3마리 < 5
    assert r.low_confidence is True
    assert r.tier == "watch"
    assert any("신뢰도" in x for x in r.recommendations)


def test_zero_bees_low_confidence():
    r = compute_risk(counts())
    assert r.bee_total == 0
    assert r.infestation_rate == 0.0
    assert r.low_confidence is True
    assert r.tier == "watch"


def test_other_disease_appends_recommendation():
    r = compute_risk(counts(normal=90, varroa=1, other=9))  # 1% safe + 다른 질병 존재
    assert r.tier == "safe"
    assert any("질병" in x for x in r.recommendations)


def test_low_confidence_score_tier_consistent():
    # 4마리(<5)·rate 75% → 저신뢰: tier=watch, score는 watch 밴드로 clamp(자기모순 방지)
    r = compute_risk(counts(normal=1, varroa=3, other=0))
    assert r.low_confidence is True
    assert r.tier == "watch"
    assert r.risk_score <= 70
    assert tier_from_score(r.risk_score) == r.tier  # score↔tier 일관


def test_estimated_count_is_none_for_yolo():
    # AIHUB Q3=B — YOLO는 응애 개체 카운트 불가 → estimated_count None
    r = compute_risk(counts(normal=50, varroa=2, other=0))
    assert r.estimated_count is None


def test_no_count_caveat_appended_when_room():
    # estimated_count None(YOLO) + safe(2문구) → 자리 남음 → 데이터 정직성 안내 append
    r = compute_risk(counts(normal=99, varroa=1, other=0))  # 1% safe
    assert r.estimated_count is None
    assert any("실측" in x for x in r.recommendations)
    assert len(r.recommendations) <= 5


def test_no_count_caveat_never_truncates_tier_copy():
    # danger(4) + other_disease(자리 없음) → caveat 생략, 그래도 ≤5 유지
    r = compute_risk(counts(normal=70, varroa=20, other=10))  # 20% danger + 질병
    assert len(r.recommendations) <= 5
    assert any("위험" in x for x in r.recommendations)
