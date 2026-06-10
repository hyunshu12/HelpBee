"""위험도 산출 — infestation_rate 기반 (v0.1.0).

설계 근거:
- apps/ai/training/configs/risk.yaml (임계·score_mapping·recommendations 단일 소스)
- apps/ai/training/datasets/AIHUB_71667.md (Q3=B: 응애 bbox = "감염된 벌 영역",
  표준 VMIR 직접 계산 불가 → infestation_rate 사용)

클래스 id: 0=bee_normal, 1=bee_with_varroa, 2=bee_other_disease.

infestation_rate(%) = bee_with_varroa / (모든 벌 인스턴스) * 100
risk_score: 0%→0, 10%→70, 20%+→100 (piecewise linear, clamp 0~100)
tier: rate < 3 safe / 3~10 watch / >10 danger
low_confidence: 탐지 벌 < min_bee_count(5) → tier watch 강제 + 안내 문구
"""

from __future__ import annotations

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


@dataclass
class RiskResult:
    risk_score: int  # 0~100
    tier: str  # "safe" | "watch" | "danger"
    infestation_rate: float  # %
    estimated_count: int | None  # YOLO는 응애 개체 카운트 불가 → None
    bee_total: int
    low_confidence: bool
    recommendations: list[str]


def _score_from_rate(rate: float, mapping: dict) -> int:
    """rate(%) → risk_score(0~100). 0→0, r70→70, r100→100 구간 선형, 양끝 clamp."""
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


def compute_risk(class_counts: dict[int, int], config: dict | None = None) -> RiskResult:
    """클래스별 인스턴스 수 → RiskResult.

    Args:
        class_counts: {class_id: count} (0/1/2). 누락 키는 0으로 간주.
        config: risk.yaml 파싱 dict (미지정 시 파일에서 로드). 테스트 주입용.
    """
    cfg_root = config or _load_config()
    cfg = cfg_root["infestation_rate"]
    safe_max = float(cfg["thresholds"]["safe_max"])  # 3.0
    watch_max = float(cfg["thresholds"]["watch_max"])  # 10.0
    min_bee = int(cfg["min_bee_count"])  # 5
    recs_all = cfg_root["recommendations"]

    normal = int(class_counts.get(CLASS_NORMAL, 0))
    varroa = int(class_counts.get(CLASS_VARROA, 0))
    other = int(class_counts.get(CLASS_OTHER, 0))
    bee_total = normal + varroa + other

    rate = (varroa / bee_total * 100.0) if bee_total > 0 else 0.0
    low_confidence = bee_total < min_bee
    score = _score_from_rate(rate, cfg["score_mapping"])

    if rate < safe_max:
        tier = "safe"
    elif rate <= watch_max:
        tier = "watch"
    else:
        tier = "danger"

    if low_confidence:
        # 탐지 벌이 적으면 진단 신뢰도가 낮음 → watch로 보수적 처리 + 안내.
        # (risk_score는 측정값 그대로 노출 — 베타에서 회귀 보정 예정)
        tier = "watch"
        recommendations = list(recs_all["low_confidence"])
    else:
        recommendations = list(recs_all[tier])
        if other > 0:
            recommendations += list(recs_all["other_disease"])

    return RiskResult(
        risk_score=score,
        tier=tier,
        infestation_rate=round(rate, 4),
        estimated_count=None,
        bee_total=bee_total,
        low_confidence=low_confidence,
        recommendations=recommendations,
    )
