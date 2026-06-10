"""추론 오케스트레이션 — engine=auto 폴백 (Hybrid C 추론 측).

설계 근거: backend-design §3(YOLO 1차 → 실패/저신뢰 시 OpenAI 폴백, 무료=폴백 X),
§3.4(폴백 트리거: 벌<min / tier 경계 ±밴드 / YOLO 에러), §3.5(OpenAI도 infestation_rate만
추정 → 동일 risk.yaml 매핑), §3.7(양쪽 실패 graceful).

순수 함수(run_analysis) — FastAPI와 분리해 엔진 주입으로 단위 검증.
"""

from __future__ import annotations

import time
from typing import Optional

from app.schemas.analysis import AnalysisResponse
from app.services import risk as risk_mod
from app.services.openai_client import OpenAIVisionClient
from app.services.preprocess import preprocess_image
from app.services.yolo_engine import YoloEngine

DEFAULT_FALLBACK_BAND = 1.0  # tier 경계 ±밴드 (%)
DEFAULT_OPENAI_CONF_FLOOR = 0.5  # OpenAI confidence 이 미만이면 low_confidence 취급


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
) -> Optional[AnalysisResponse]:
    """OpenAI 폴백 시도. 실패 시 None."""
    try:
        ores = openai.analyze(jpeg)
    except Exception:  # noqa: BLE001 - 폴백 실패는 graceful로 흡수
        return None
    rate = ores.infestation_rate
    low_conf = ores.confidence < DEFAULT_OPENAI_CONF_FLOOR
    tier = "watch" if low_conf else risk_mod.tier_from_rate(rate, config)
    return AnalysisResponse(
        risk_score=risk_mod.score_from_rate(rate, config),
        tier=tier,
        estimated_count=None,
        confidence=round(ores.confidence, 4),
        recommendations=risk_mod.recommendations_for(
            tier, low_confidence=low_conf, config=config
        ),
        model_version=ores.model_version,
        prompt_version=ores.prompt_version,
        latency_ms=0,
        cost_estimate_usd=round(ores.cost_usd, 6),
        raw_payload={"infestation_rate": rate, "fallback_from": yolo_summary},
        engine_used="openai",
        fallback_reason=fallback_reason,
    )


def run_analysis(
    jpeg: bytes,
    *,
    engine: str = "auto",
    yolo: YoloEngine,
    openai: Optional[OpenAIVisionClient] = None,
    prompt_version: str = "varroa@1.0",
    fallback_band: float = DEFAULT_FALLBACK_BAND,
    config: dict | None = None,
) -> AnalysisResponse:
    """이미지 1장 → AnalysisResponse.

    engine: "auto"(유료, YOLO→OpenAI 폴백 허용) | "yolo"(무료, 폴백 금지).
    preprocess 실패(ImageDecodeError/ImageTooLargeError)는 호출자(라우터)가 4xx로 매핑.
    """
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
