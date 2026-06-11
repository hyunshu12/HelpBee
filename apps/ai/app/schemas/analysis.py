"""AI 추론 응답 스키마 (Pydantic v2).

설계 근거: backend-design §6, apps/ai/CLAUDE.md §6, §3.7(graceful 실패).
- tier 3분법 단일(safe/watch/danger). 마스터플랜 4분법(caution/warning/critical) 폐기.
- Hybrid C: engine_used / fallback_reason 메타를 실어 apps/api가 정책·저장에 사용.
- 실패는 에러 대신 graceful(risk_score=None, tier="watch")로 200 반환(UX 비차단).
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, field_validator

Tier = Literal["safe", "watch", "danger"]
Engine = Literal["yolo", "openai"]

_DEFAULT_FAILURE_RECS = ["AI 분석에 실패했습니다. 잠시 후 다시 시도해 주세요."]


class AnalysisResponse(BaseModel):
    risk_score: int | None  # 0~100 (clamp). 실패 시 None.
    tier: Tier
    estimated_count: int | None = None  # 응애 개체 수(YOLO는 None)
    confidence: float = 0.0  # 0.0~1.0
    recommendations: list[str] = []
    model_version: str
    prompt_version: str | None = None  # OpenAI만 채움
    latency_ms: int = 0
    cost_estimate_usd: float | None = None  # OpenAI만 채움
    raw_payload: dict = {}
    engine_used: Engine | None = None  # 실제 사용된 엔진 (실패 시 None)
    fallback_reason: str | None = None  # YOLO→OpenAI 폴백 사유

    @field_validator("risk_score")
    @classmethod
    def _clamp_score(cls, v: int | None) -> int | None:
        if v is None:
            return None
        return max(0, min(100, v))

    @field_validator("confidence")
    @classmethod
    def _clamp_confidence(cls, v: float) -> float:
        return max(0.0, min(1.0, float(v)))

    @classmethod
    def graceful_failure(
        cls,
        *,
        model_version: str,
        reason: str,
        latency_ms: int = 0,
        recommendations: list[str] | None = None,
    ) -> "AnalysisResponse":
        """양쪽 엔진 실패/타임아웃/예산초과 시 200으로 반환할 graceful 페이로드.

        apps/api는 이를 status='failed'로 저장하되 HTTP 200 envelope로 비차단(§3.7).
        """
        return cls(
            risk_score=None,
            tier="watch",
            estimated_count=None,
            confidence=0.0,
            recommendations=recommendations or list(_DEFAULT_FAILURE_RECS),
            model_version=model_version,
            prompt_version=None,
            latency_ms=latency_ms,
            cost_estimate_usd=None,
            raw_payload={"error_reason": reason},
            engine_used=None,
            fallback_reason=None,
        )
