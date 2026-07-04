"""위험도 산출 — infestation_rate 기반 (v0.1.0).

설계 근거:
- apps/ai/training/configs/risk.yaml (임계·score_mapping·recommendations 단일 소스)
- apps/ai/training/datasets/AIHUB_71667.md (Q3=B: 응애 bbox = "감염된 벌 영역",
  표준 VMIR 직접 계산 불가 → infestation_rate 사용)
- backend-design §3.5: OpenAI 폴백도 infestation_rate만 추정 → 동일 매핑 함수로 risk_score
  산출(엔진 전환 시 위험도 점프 방지). 그래서 rate→risk 프리미티브를 공개한다.

클래스 id: 0=bee_normal, 1=bee_with_varroa, 2=bee_other_disease.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import yaml

CLASS_NORMAL = 0
CLASS_VARROA = 1
CLASS_OTHER = 2

# apps/ai/app/services/risk.py → parents[2] = apps/ai
_CONFIG_PATH = Path(__file__).resolve().parents[2] / "training" / "configs" / "risk.yaml"


@lru_cache(maxsize=1)
def _load_config() -> dict:
    with open(_CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _cfg(config: dict | None) -> dict:
    return config or _load_config()


@dataclass
class RiskResult:
    risk_score: int  # 0~100
    tier: str  # "safe" | "watch" | "danger"
    infestation_rate: float  # %
    estimated_count: int | None  # YOLO는 응애 개체 카운트 불가 → None
    bee_total: int
    low_confidence: bool
    recommendations: list[str]


def score_from_rate(rate: float, config: dict | None = None) -> int:
    """rate(%) → risk_score(0~100). 0→0, r70→70, r100→100 구간 선형, 양끝 clamp."""
    mapping = _cfg(config)["infestation_rate"]["score_mapping"]
    r70 = float(mapping["rate_at_score_70"])  # 10.0
    r100 = float(mapping["rate_at_score_100"])  # 20.0
    if rate <= 0:
        score = 0.0
    elif rate <= r70:
        score = (rate / r70) * 70.0
    else:
        span = max(r100 - r70, 1e-9)
        score = 70.0 + (rate - r70) / span * 30.0
    return int(max(0, min(100, round(score))))


def tier_from_rate(rate: float, config: dict | None = None) -> str:
    th = _cfg(config)["infestation_rate"]["thresholds"]
    if rate < float(th["safe_max"]):  # <3 safe
        return "safe"
    if rate <= float(th["watch_max"]):  # 3~10 watch
        return "watch"
    return "danger"  # >10


def thresholds(config: dict | None = None) -> tuple[float, float]:
    """(safe_max, watch_max) — tier 경계. 폴백 ±밴드 판정에 사용."""
    th = _cfg(config)["infestation_rate"]["thresholds"]
    return float(th["safe_max"]), float(th["watch_max"])


def band_scores(config: dict | None = None) -> tuple[int, int]:
    """(safe_ceiling_score, watch_ceiling_score) — 임계 rate를 score로 환산(21,70)."""
    safe_max, watch_max = thresholds(config)
    return score_from_rate(safe_max, config), score_from_rate(watch_max, config)


def tier_from_score(score: int, config: dict | None = None) -> str:
    """score → tier. tier는 항상 risk_score 밴드에서 파생(저장 행 자기모순 방지)."""
    safe_s, watch_s = band_scores(config)
    if score < safe_s:
        return "safe"
    if score <= watch_s:
        return "watch"
    return "danger"


def recommendations_for(
    tier: str,
    *,
    low_confidence: bool = False,
    has_other_disease: bool = False,
    count_available: bool = True,
    config: dict | None = None,
) -> list[str]:
    recs_all = _cfg(config)["recommendations"]
    if low_confidence:
        return list(recs_all["low_confidence"])
    out = list(recs_all[tier])
    if has_other_disease:
        out += list(recs_all["other_disease"])
    out = out[:5]  # CLAUDE.md §6: recommendations ≤5
    # 응애 개체 카운트 불가(YOLO) → 자리가 남을 때만 데이터 정직성 안내 append.
    # tier/other_disease 문구를 절대 밀어내지 않음(자리 없으면 생략).
    if not count_available and len(out) < 5:
        caveat = recs_all.get("no_count_caveat")
        if caveat:
            out.append(caveat[0] if isinstance(caveat, list) else caveat)
    return out[:5]


def min_bee_count(config: dict | None = None) -> int:
    return int(_cfg(config)["infestation_rate"]["min_bee_count"])


def compute_risk(class_counts: dict[int, int], config: dict | None = None) -> RiskResult:
    """클래스별 인스턴스 수 → RiskResult (YOLO 경로).

    Args:
        class_counts: {class_id: count} (0/1/2). 누락 키는 0으로 간주.
        config: risk.yaml 파싱 dict (미지정 시 파일 로드). 테스트 주입용.
    """
    normal = int(class_counts.get(CLASS_NORMAL, 0))
    varroa = int(class_counts.get(CLASS_VARROA, 0))
    other = int(class_counts.get(CLASS_OTHER, 0))
    bee_total = normal + varroa + other

    rate = (varroa / bee_total * 100.0) if bee_total > 0 else 0.0
    if not math.isfinite(rate):
        rate = 0.0
    rate = max(0.0, rate)
    low_confidence = bee_total < min_bee_count(config)
    score = score_from_rate(rate, config)
    if low_confidence:
        # 저신뢰: 측정 불안정 → score를 watch 밴드로 clamp해 tier와 일관(자기모순 방지)
        safe_s, watch_s = band_scores(config)
        score = max(safe_s, min(watch_s, score))
    tier = tier_from_score(score, config)
    estimated_count = None  # YOLO는 응애 개체 카운트 불가(AIHUB Q3=B)
    recommendations = recommendations_for(
        tier,
        low_confidence=low_confidence,
        has_other_disease=other > 0,
        count_available=estimated_count is not None,
        config=config,
    )

    return RiskResult(
        risk_score=score,
        tier=tier,
        infestation_rate=round(rate, 4),
        estimated_count=estimated_count,
        bee_total=bee_total,
        low_confidence=low_confidence,
        recommendations=recommendations,
    )
