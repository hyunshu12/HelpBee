"""런타임 설정 (env). 라우터/deps에서 사용. 테스트는 core 순수 모듈을 직접 검증."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

# apps/ai/.env 자동 로드 (이미 설정된 환경변수가 우선 — override=False 기본).
# uvicorn을 어느 cwd에서 띄우든 config.py 기준으로 .env를 찾는다.
load_dotenv(Path(__file__).resolve().parents[2] / ".env")


@dataclass
class Settings:
    ai_internal_hmac_secret: str
    image_allowlist_hosts: list[str]
    image_fetch_allow_http: bool
    # two-stage 서빙 (스펙 v2.2 §8). AI_ENGINE=two-stage 면 engine=yolo/auto 요청의 1차 엔진이
    # two-stage, yolo-v1 이면 기존 v0.1.0 단일 스테이지(롤백용).
    ai_engine: str = "two-stage"
    two_stage_model_version: str = "v0.2.0"
    two_stage_cache_dir: str = str(Path.home() / ".cache" / "helpbee" / "two-stage")
    models_bucket: str = "helpbee-models"
    ai_internal_budget_s: float = 80.0  # 타임아웃 체인: 모바일 ≥95s ≥ ai-client 90s ≥ 이 값


def load_settings() -> Settings:
    hosts = os.getenv(
        "IMAGE_ALLOWLIST_HOSTS", "s3.ap-northeast-2.amazonaws.com,cdn.helpbee.kr"
    )
    return Settings(
        ai_internal_hmac_secret=os.environ.get("AI_INTERNAL_HMAC_SECRET", ""),
        image_allowlist_hosts=[h.strip() for h in hosts.split(",") if h.strip()],
        image_fetch_allow_http=os.getenv("IMAGE_FETCH_ALLOW_HTTP", "false").lower() == "true",
        ai_engine=os.getenv("AI_ENGINE", "two-stage"),
        two_stage_model_version=os.getenv("TWO_STAGE_MODEL_VERSION", "v0.2.0"),
        two_stage_cache_dir=os.getenv("TWO_STAGE_CACHE_DIR")
        or str(Path.home() / ".cache" / "helpbee" / "two-stage"),  # 빈 값 = 기본
        models_bucket=os.getenv("AWS_S3_MODELS_BUCKET", "helpbee-models"),
        ai_internal_budget_s=float(os.getenv("AI_INTERNAL_BUDGET_S", "80")),
    )


settings = load_settings()
