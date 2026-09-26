"""추론 오케스트레이션 — engine=auto 폴백 (Hybrid C 추론 측).

설계 근거: backend-design §3(YOLO 1차 → 실패/저신뢰 시 OpenAI 폴백, 무료=폴백 X),
§3.4(폴백 트리거: 벌<min / tier 경계 ±밴드 / YOLO 에러), §3.5(OpenAI도 infestation_rate만
추정 → 동일 risk.yaml 매핑), §3.7(양쪽 실패 graceful).

순수 함수(run_analysis) — FastAPI와 분리해 엔진 주입으로 단위 검증.
"""

from __future__ import annotations

import math
import time
from pathlib import Path
from typing import Optional

import yaml

from app.schemas.analysis import AnalysisResponse
from app.services import risk as risk_mod
from app.services import vdi as vdi_mod
from app.services.openai_client import OpenAIVisionClient
from app.services.preprocess import decode_rgb, preprocess_image
from app.services.quality import assess_quality
from app.services.vdi import VdiConfig
from app.services.yolo_engine import YoloEngine

DEFAULT_FALLBACK_BAND = 1.0  # tier 경계 ±밴드 (%)
DEFAULT_OPENAI_CONF_FLOOR = 0.5  # OpenAI confidence 이 미만이면 low_confidence 취급
DEFAULT_BUDGET_S = 80.0  # AI 내부 예산 — 타임아웃 체인 모바일 ≥95s ≥ ai-client 90s ≥ 이 값 (스펙 §8)
MIN_BEES_NO_FALLBACK = 30  # 유료 폴백 트리거: tier insufficient 또는 bee_total < 30 (스펙 §5.5)
LEGACY_TIER = {"low": "safe", "elevated": "watch", "high": "danger", "insufficient": "unknown"}
_DEFAULT_VDI_YAML = Path(__file__).resolve().parents[2] / "training" / "configs" / "vdi.yaml"
RAW_BOXES_CAP = 1500  # = two_stage_engine.CROP_CAP (Stage-2 크롭 상한)


def compact_boxes(bees, cap: int = RAW_BOXES_CAP) -> list[list[float]]:
    """two-stage 벌 박스 → 저장용 [[x1,y1,x2,y2,p], ...] (좌표 int 반올림, p 3자리, cap 개 이하)."""
    return [[int(round(v)) for v in b.box] + [round(float(b.p_infested), 3)] for b in list(bees)[:cap]]


def _default_vdi_extras() -> dict:
    try:
        return yaml.safe_load(_DEFAULT_VDI_YAML.read_text(encoding="utf-8")) or {}
    except OSError:  # pragma: no cover - 배포 이미지는 training/configs 포함
        return {}


def recs_for_tier(tier: str, extras: dict) -> list[str]:
    """vdi.yaml `recommendations` 에서 tier 문구 + (판독 가능 tier 면) 다음 권장 점검 시기."""
    recs = extras.get("recommendations") or {}
    out = list(recs.get(tier) or [])
    windows = recs.get("next_check_windows") or []
    if tier != "insufficient" and windows:
        out.append("다음 권장 점검 시기: " + " · ".join(windows))
    return out


def _needs_fallback(
    risk: risk_mod.RiskResult, *, band: float, config: dict | None
) -> Optional[str]:
    """폴백 사유 반환 (없으면 None)."""
    if risk.low_confidence:
        return "low_confidence"
    for boundary in risk_mod.thresholds(config):
        if abs(risk.infestation_rate - boundary) <= band:
            return "boundary"
    return None


def _yolo_summary(yres, risk: risk_mod.RiskResult) -> dict:
    return {
        "yolo_model_version": yres.model_version,
        "yolo_confidence": round(yres.confidence, 4),
        "yolo_bee_total": risk.bee_total,
        "yolo_infestation_rate": risk.infestation_rate,
    }


def _openai_response(
    jpeg: bytes,
    openai: OpenAIVisionClient,
    config: dict | None,
    *,
    fallback_reason: str,
    yolo_summary: dict,
    vdi_cfg: VdiConfig | None = None,
    vdi_extras: dict | None = None,
) -> Optional[AnalysisResponse]:
    """OpenAI 폴백 시도. 실패(호출/파싱/매핑 어디든) 시 None → 호출부가 graceful 처리.

    매핑(score/tier)까지 try 범위에 포함 — OpenAI가 NaN/Inf/비정상 rate를 줘도
    예외가 run_analysis 밖으로 새어 500이 되지 않도록(§3.7 비차단).
    """
    try:
        ores = openai.analyze(jpeg)
        rate = ores.infestation_rate
        if not math.isfinite(rate):
            rate = 0.0
        rate = max(0.0, rate)
        low_conf = ores.confidence < DEFAULT_OPENAI_CONF_FLOOR
        score = risk_mod.score_from_rate(rate, config)
        if low_conf:
            safe_s, watch_s = risk_mod.band_scores(config)
            score = max(safe_s, min(watch_s, score))  # tier와 일관
        tier = risk_mod.tier_from_score(score, config)
        if vdi_cfg is not None:
            # OpenAI shim (스펙 A5·§8): rate → 새 계약. bees 없음·bee_total null·보정 안 함.
            # risk_score 는 risk.py(동결) 점수 그대로, tier 는 같은 반열림 규칙(표시값 기준).
            shown = vdi_mod.display(rate)
            new_tier = vdi_mod.tier_from_display(shown, vdi_cfg, bee_total=1, quality_ok=True)
            return AnalysisResponse(
                risk_score=score,
                tier=new_tier,
                tier_legacy=LEGACY_TIER[new_tier],
                confidence=round(ores.confidence, 4),
                recommendations=recs_for_tier(new_tier, vdi_extras or {}),
                model_version=ores.model_version,
                prompt_version=ores.prompt_version,
                cost_estimate_usd=round(ores.cost_usd, 6),
                raw_payload={"infestation_rate": rate, "fallback_from": yolo_summary,
                             "low_confidence": low_conf},
                engine_used="openai",
                fallback_reason=fallback_reason,
                vdi=rate,
                vdi_display=shown,
                vdi_raw=rate,
                corrected=False,
                sampling_ci95=None,
                bee_total=None,
                bee_infested=None,
                bees=[],
                model_versions=None,  # API 가 two-stage ai_models 행을 고르지 않게
            )
        return AnalysisResponse(
            risk_score=score,
            tier=tier,
            estimated_count=None,
            confidence=round(ores.confidence, 4),
            recommendations=risk_mod.recommendations_for(
                tier, low_confidence=low_conf, count_available=False, config=config
            ),
            model_version=ores.model_version,
            prompt_version=ores.prompt_version,
            latency_ms=0,
            cost_estimate_usd=round(ores.cost_usd, 6),
            raw_payload={"infestation_rate": rate, "fallback_from": yolo_summary},
            engine_used="openai",
            fallback_reason=fallback_reason,
        )
    except Exception:  # noqa: BLE001 - 폴백 실패(호출/파싱/매핑)는 graceful로 흡수
        return None


def run_analysis(
    jpeg: bytes,
    *,
    engine: str = "auto",
    yolo: YoloEngine | None = None,
    two_stage=None,
    openai: Optional[OpenAIVisionClient] = None,
    prompt_version: str = "varroa@1.0",
    fallback_band: float = DEFAULT_FALLBACK_BAND,
    config: dict | None = None,
    vdi_cfg: VdiConfig | None = None,
    vdi_extras: dict | None = None,
    budget_s: float = DEFAULT_BUDGET_S,
) -> AnalysisResponse:
    """이미지 1장 → AnalysisResponse.

    engine: "auto"(유료, YOLO→OpenAI 폴백 허용) | "yolo"(무료, 폴백 금지).
    preprocess 실패(ImageDecodeError/ImageTooLargeError)는 호출자(라우터)가 4xx로 매핑.
    two_stage 가 주어지면 two-stage 경로(스펙 v2.2), 아니면 v0.1.0 단일 스테이지(롤백용).
    """
    if two_stage is not None:
        return _run_two_stage(
            jpeg, engine=engine, two_stage=two_stage, openai=openai, config=config,
            vdi_cfg=vdi_cfg, vdi_extras=vdi_extras, budget_s=budget_s,
        )
    if yolo is None:
        raise ValueError("run_analysis: yolo 또는 two_stage 엔진이 필요하다")
    pre = preprocess_image(jpeg)  # 입력 검증 실패 시 raise → 라우터 4xx
    t0 = time.monotonic()
    fallback_allowed = engine == "auto" and openai is not None

    # 1) YOLO 1차
    try:
        yres = yolo.detect(pre.jpeg)
        risk = risk_mod.compute_risk(yres.class_counts, config)
    except Exception as exc:  # noqa: BLE001
        yolo_error = str(exc)
    else:
        reason = _needs_fallback(risk, band=fallback_band, config=config)
        if fallback_allowed and reason is not None:
            fb = _openai_response(
                pre.jpeg, openai, config,
                fallback_reason=reason, yolo_summary=_yolo_summary(yres, risk),
            )
            if fb is not None:
                fb.latency_ms = int((time.monotonic() - t0) * 1000)
                return fb
        # YOLO 결과 그대로 (폴백 불필요 / 무료 / 폴백 실패)
        return AnalysisResponse(
            risk_score=risk.risk_score,
            tier=risk.tier,
            estimated_count=risk.estimated_count,
            confidence=round(yres.confidence, 4),
            recommendations=risk.recommendations,
            model_version=yres.model_version,
            prompt_version=None,
            latency_ms=int((time.monotonic() - t0) * 1000),
            cost_estimate_usd=None,
            raw_payload={
                "infestation_rate": risk.infestation_rate,
                "bee_total": risk.bee_total,
                "class_counts": yres.class_counts,
            },
            engine_used="yolo",
            fallback_reason=None,
        )

    # 2) YOLO 실패 → (유료면) OpenAI 폴백
    if fallback_allowed:
        fb = _openai_response(
            pre.jpeg, openai, config,
            fallback_reason="yolo_error", yolo_summary={"error": yolo_error},
        )
        if fb is not None:
            fb.latency_ms = int((time.monotonic() - t0) * 1000)
            return fb

    # 3) 양쪽 실패 / 무료 YOLO 실패 → graceful (200 비차단)
    model_version = getattr(yolo, "model_version", "yolo")
    result = AnalysisResponse.graceful_failure(
        model_version=model_version, reason=yolo_error or "inference_failed"
    )
    result.latency_ms = int((time.monotonic() - t0) * 1000)
    return result


def _openai_jpeg(jpeg: bytes) -> bytes:
    """OpenAI 폴백은 기존대로 1024 축소본을 보낸다(비용·지연) — 축소 우회는 two-stage 전용."""
    try:
        return preprocess_image(jpeg).jpeg
    except Exception:  # noqa: BLE001 - 축소 실패 시 원본 전달(OpenAI 실패는 _openai_response 가 흡수)
        return jpeg


def _fallback_reason_two_stage(tier: str, bee_total: int) -> Optional[str]:
    """유료 폴백 트리거(스펙 §5.5): tier insufficient(0마리·품질 실패) 또는 bee_total < 30."""
    if tier == "insufficient":
        return "insufficient"
    if bee_total < MIN_BEES_NO_FALLBACK:
        return "low_count"
    return None


def _run_two_stage(
    jpeg: bytes,
    *,
    engine: str,
    two_stage,
    openai: Optional[OpenAIVisionClient],
    config: dict | None,
    vdi_cfg: VdiConfig | None,
    vdi_extras: dict | None,
    budget_s: float,
) -> AnalysisResponse:
    image = decode_rgb(jpeg)  # 축소 없음(MAX_EDGE 우회는 이 경로 전용). 디코드 실패 → 라우터 4xx
    t0 = time.monotonic()
    fallback_allowed = engine == "auto" and openai is not None
    cfg = vdi_cfg or two_stage.vdi_config()
    if vdi_extras is None:
        getter = getattr(two_stage, "vdi_extras", None)
        vdi_extras = getter() if callable(getter) else _default_vdi_extras()
    extras = vdi_extras or {}
    model_version = getattr(two_stage, "model_version", "helpbee-two-stage")

    try:
        res = two_stage.analyze(image, cfg, deadline=t0 + budget_s)
    except Exception as exc:  # noqa: BLE001 - 엔진 실패/예산 초과 → 폴백 또는 graceful
        err = f"{type(exc).__name__}: {exc}"
        if fallback_allowed:
            fb = _openai_response(
                _openai_jpeg(jpeg), openai, config, fallback_reason="two_stage_error",
                yolo_summary={"error": err}, vdi_cfg=cfg, vdi_extras=extras,
            )
            if fb is not None:
                fb.latency_ms = int((time.monotonic() - t0) * 1000)
                return fb
        out = AnalysisResponse.graceful_failure(model_version=model_version, reason=err)
        out.latency_ms = int((time.monotonic() - t0) * 1000)
        return out

    qcfg = extras.get("quality") or {}
    q = assess_quality(
        image, [b.box for b in res.bees], extras.get("capture_floor_px_per_mm"),
        blur_min=float(qcfg.get("blur_laplacian_min", 100)),
        exposure=tuple(qcfg.get("exposure_mean", (40, 215))),
    )
    k, n = res.bee_infested, res.bee_total
    agg = vdi_mod.aggregate([(k, n)], cfg, quality_ok=q["ok"])
    tier = agg["tier"]
    has = n > 0
    ps = [b.p_infested for b in res.bees]
    resp = AnalysisResponse(
        risk_score=risk_mod.score_from_rate(agg["vdi"], config) if has else None,
        tier=tier,
        tier_legacy=LEGACY_TIER[tier],
        estimated_count=None,
        # 분류 확신도 평균 max(p, 1-p) — 벌이 없으면 0.
        confidence=round(float(sum(max(p, 1 - p) for p in ps) / len(ps)), 4) if ps else 0.0,
        recommendations=recs_for_tier(tier, extras),
        model_version=model_version,
        latency_ms=int((time.monotonic() - t0) * 1000),
        raw_payload={
            "sampled": res.sampled,
            "stage_latency_ms": res.stage_latency_ms,
            "image_hw": list(image.shape[:2]),
            "tau": cfg.tau,
            # 어드민 dual 뷰 bbox 오버레이용 소형 목록 — [x1,y1,x2,y2,p] (int 좌표, p 소수 3자리).
            # bees[](dict·float)는 저장하지 않고 이것만 raw_response 에 남긴다(≤ crop cap ≈ 40 KB).
            "boxes": compact_boxes(res.bees),
        },
        engine_used="yolo",
        vdi=agg["vdi"] if has else None,
        vdi_display=agg["vdi_display"] if has else None,
        vdi_raw=agg["raw"] if has else None,
        corrected=vdi_mod._usable(cfg),
        sampling_ci95=agg["sampling_ci95"] if has else None,
        bee_total=n,
        bee_infested=k,
        bees=[{"box": b.box, "p_infested": b.p_infested, "infested": b.infested} for b in res.bees],
        evidence=res.evidence,
        quality=q,
        model_versions=res.model_versions,
    )

    reason = _fallback_reason_two_stage(tier, n)
    if fallback_allowed and reason is not None:
        fb = _openai_response(
            _openai_jpeg(jpeg), openai, config, fallback_reason=reason,
            yolo_summary={"bee_total": n, "bee_infested": k, "tier": tier, "quality_ok": q["ok"],
                          "model_versions": res.model_versions},
            vdi_cfg=cfg, vdi_extras=extras,
        )
        if fb is not None:
            fb.latency_ms = int((time.monotonic() - t0) * 1000)
            return fb
    return resp
