"""엔진 의존성 팩토리 (lazy 싱글톤).

런타임(onnxruntime/boto3/openai/env) 의존이라 본 환경 단위 테스트 대상 아님 —
통합 검증 대상(pragma no cover). 라우터는 이 팩토리로 엔진을 주입받고,
오케스트레이터(run_analysis)는 주입된 엔진에만 의존(테스트는 Fake 주입).
"""

from __future__ import annotations

import os
from functools import lru_cache

from app.services.openai_client import OpenAIVisionClient
from app.services.yolo_engine import OnnxYoloEngine


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
def get_openai_client() -> OpenAIVisionClient:  # pragma: no cover - 런타임 의존
    from openai import OpenAI  # lazy import

    return OpenAIVisionClient(
        OpenAI(api_key=os.environ["OPENAI_API_KEY"]),
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini-2024-07-18"),
        prompt_version=os.getenv("PROMPT_VERSION", "varroa@1.0"),
    )
