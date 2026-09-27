"""VDI(가시 감염 지수) 수식 — 평가(training/eval_e2e.py)와 서빙(계획 2 two_stage_engine)이 공유."""
from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

import yaml
from scipy.stats import beta


@dataclass
class VdiConfig:
    tau: float
    tpr: float
    fpr: float
    corrected: bool
    elevated: float = 3.0
    high: float = 10.0
    platt: tuple[float, float] = (1.0, 0.0)


def load_vdi_config(path: Path) -> VdiConfig:
    """training/train_stage2.write_vdi_yaml 산출물을 읽는다. platt 는 {a, b} (계획 2 서빙이 사용)."""
    d = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    pl = d.get("platt", {"a": 1.0, "b": 0.0})
    return VdiConfig(
        d["tau"],
        d["tpr"],
        d["fpr"],
        bool(d["corrected"]),
        d["thresholds"]["elevated"],
        d["thresholds"]["high"],
        (float(pl["a"]), float(pl["b"])),
    )


def _usable(cfg: VdiConfig) -> bool:
    return cfg.corrected and (cfg.tpr - cfg.fpr) >= 0.5


def rogan_gladen(raw_pct: float, cfg: VdiConfig) -> float:
    """Rogan–Gladen 보정. clip [0,100]; corrected=False 또는 tpr-fpr<0.5 면 raw 그대로."""
    if not _usable(cfg):
        return raw_pct
    return min(100.0, max(0.0, (raw_pct - cfg.fpr * 100) / (cfg.tpr - cfg.fpr)))


def jeffreys_ci(k: int, n: int) -> tuple[float, float]:
    """Jeffreys 95% 구간 (% 단위)."""
    if n == 0:
        return (0.0, 100.0)
    lo = 0.0 if k == 0 else float(beta.ppf(0.025, k + 0.5, n - k + 0.5)) * 100
    hi = 100.0 if k == n else float(beta.ppf(0.975, k + 0.5, n - k + 0.5)) * 100
    return (lo, hi)


def corrected_ci(k: int, n: int, cfg: VdiConfig) -> tuple[float, float]:
    """Jeffreys 끝점을 Rogan–Gladen 으로 사상. 하한 0 floor, 상한은 raw 상한 이상."""
    lo, hi = jeffreys_ci(k, n)
    if not _usable(cfg):
        return (lo, hi)

    def f(v: float) -> float:
        return (v - cfg.fpr * 100) / (cfg.tpr - cfg.fpr)

    return (max(0.0, f(lo)), min(100.0, max(hi, f(hi))))  # 상한은 raw 상한 이상 — [0,0] 붕괴 방지


def display(v: float) -> str:
    """Decimal ROUND_HALF_UP 소수 1자리 (repr 경유 — 2.95 → "3.0")."""
    return str(Decimal(repr(float(v))).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))


def tier_from_display(s: str, cfg: VdiConfig, bee_total: int, quality_ok: bool) -> str:
    """표시 문자열 기준 반열림 구간: [0,elevated) low / [elevated,high) elevated / [high,∞) high."""
    if bee_total == 0 or not quality_ok:
        return "insufficient"
    v = Decimal(s)
    if v < Decimal(str(cfg.elevated)):
        return "low"
    if v < Decimal(str(cfg.high)):
        return "elevated"
    return "high"


def aggregate(counts: list[tuple[int, int]], cfg: VdiConfig, quality_ok: bool = True) -> dict:
    """(감염 벌 수, 전체 벌 수) 목록을 카운트로 합산(퍼센트 평균 아님)해 VDI·CI·tier 산출."""
    k, n = sum(c[0] for c in counts), sum(c[1] for c in counts)
    raw = (k / n * 100) if n else 0.0
    v = rogan_gladen(raw, cfg)
    lo, hi = corrected_ci(k, n, cfg)
    d = display(v)
    return {
        "bee_infested": k,
        "bee_total": n,
        "raw": raw,
        "vdi": v,
        "vdi_display": d,
        "sampling_ci95": (lo, hi),
        "tier": tier_from_display(d, cfg, n, quality_ok),
    }
