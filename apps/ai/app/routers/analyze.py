"""POST /analyze — 단일 이미지 진단 (Hybrid C 수신측).

계약(backend-design §3.2/§3.8, apps/api ai-client.ts와 정합):
  요청: JSON {image_url: str, engine: 'auto'|'yolo'} + Authorization: Bearer <내부 HMAC>
        + x-request-id (bearer의 request_id와 일치해야 함)
  처리: 내부 인증 검증 → image_url SSRF 가드 fetch → run_analysis(engine=auto 폴백)
  응답: AnalysisResponse(JSON). 입력 오류만 4xx, 추론 실패는 graceful 200.

런타임(fastapi/엔진/네트워크) 의존이라 단위 테스트는 core(internal_auth/image_fetch)와
orchestrator에서 수행 — 본 어댑터는 통합 검증 대상(pragma).
"""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel

from app.core.config import settings
from app.core.image_fetch import UnsafeUrlError, fetch_image
from app.core.internal_auth import InternalAuthError, verify_internal_bearer
from app.deps import get_openai_client, get_yolo_engine
from app.services.orchestrator import run_analysis
from app.services.preprocess import ImageDecodeError, ImageTooLargeError

router = APIRouter()


class AnalyzeRequest(BaseModel):
    image_url: str
    engine: Literal["auto", "yolo"] = "auto"


async def require_internal(  # pragma: no cover - 통합 검증 대상
    authorization: str | None = Header(default=None),
    x_request_id: str | None = Header(default=None),
) -> dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing internal token")
    token = authorization[len("Bearer ") :]
    try:
        return verify_internal_bearer(
            settings.ai_internal_hmac_secret, token, request_id=x_request_id
        )
    except InternalAuthError:
        raise HTTPException(status_code=401, detail="invalid internal token")


@router.post("/analyze")
async def analyze(  # pragma: no cover - 통합 검증 대상
    body: AnalyzeRequest,
    _claims: dict = Depends(require_internal),
):
    try:
        image = fetch_image(
            body.image_url,
            allowlist_hosts=settings.image_allowlist_hosts,
            allow_http=settings.image_fetch_allow_http,
        )
    except UnsafeUrlError:
        raise HTTPException(status_code=400, detail="unsafe or invalid image url")

    try:
        result = run_analysis(
            image,
            engine=body.engine,
            yolo=get_yolo_engine(),
            openai=get_openai_client() if body.engine == "auto" else None,
        )
    except ImageDecodeError:
        raise HTTPException(status_code=422, detail="invalid image")
    except ImageTooLargeError:
        raise HTTPException(status_code=413, detail="image too large (>10MB)")
    return result.model_dump()
