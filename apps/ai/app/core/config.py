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


def load_settings() -> Settings:
    hosts = os.getenv(
        "IMAGE_ALLOWLIST_HOSTS", "s3.ap-northeast-2.amazonaws.com,cdn.helpbee.kr"
    )
    return Settings(
        ai_internal_hmac_secret=os.environ.get("AI_INTERNAL_HMAC_SECRET", ""),
        image_allowlist_hosts=[h.strip() for h in hosts.split(",") if h.strip()],
        image_fetch_allow_http=os.getenv("IMAGE_FETCH_ALLOW_HTTP", "false").lower() == "true",
    )


settings = load_settings()
