"""엔진 의존성 팩토리 (lazy 싱글톤).

런타임(onnxruntime/boto3/openai/env) 의존이라 본 환경 단위 테스트 대상 아님 —
통합 검증 대상(pragma no cover). 라우터는 이 팩토리로 엔진을 주입받고,
오케스트레이터(run_analysis)는 주입된 엔진에만 의존(테스트는 Fake 주입).
"""

from __future__ import annotations

import logging
import os
from functools import lru_cache

from app.services.openai_client import OpenAIVisionClient
from app.services.yolo_engine import OnnxYoloEngine

_log = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def get_yolo_engine() -> OnnxYoloEngine:  # pragma: no cover - 런타임 의존
    return OnnxYoloEngine(
        model_version=os.getenv("YOLO_MODEL_VERSION", "v0.1.0"),
        s3_bucket=os.getenv("AWS_S3_MODELS_BUCKET", "helpbee-models"),
        # YOLO_CACHE_DIR overridable so the weight cache can live in a writable
        # path on dev machines (the prod default /var/cache needs root on macOS).
        cache_dir=os.getenv("YOLO_CACHE_DIR", "/var/cache/helpbee/yolo"),
    )


@lru_cache(maxsize=1)
def get_openai_client() -> OpenAIVisionClient | None:  # pragma: no cover - 런타임 의존
    """OpenAI를 쓸 수 없으면 raise 대신 None.

    run_analysis 는 `openai is None` 이면 폴백을 끄고 YOLO 결과를 그대로 쓴다
    (`fallback_allowed = engine == "auto" and openai is not None`).

    키 미설정이나 패키지 미설치(추론 서버는 CPU용 requirements 라 openai 가 없다)는
    **설정 상태이지 요청 실패가 아니다.** 여기서 raise 하면 engine=auto 로 오는
    유료 사용자의 분석이 통째로 500 → `ai_unavailable` 로 죽는다. CLAUDE.md §6의
    "실패해도 UX를 막지 않는다" 원칙에 따라 조용히 YOLO 단독으로 내려간다.
    """
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        _log.warning("OPENAI_API_KEY 미설정 — engine=auto 요청도 YOLO 단독으로 처리한다")
        return None

    try:
        from openai import OpenAI  # lazy import
    except ModuleNotFoundError:
        _log.warning("openai 패키지 미설치 — engine=auto 요청도 YOLO 단독으로 처리한다")
        return None

    return OpenAIVisionClient(
        OpenAI(api_key=api_key),
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini-2024-07-18"),
        prompt_version=os.getenv("PROMPT_VERSION", "varroa@1.0"),
    )
