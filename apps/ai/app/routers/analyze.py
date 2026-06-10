"""POST /analyze — 단일 이미지 진단 (engine=auto YOLO→OpenAI 폴백 / yolo=무료).

얇은 어댑터: 입력(멀티파트) → run_analysis(오케스트레이터) → JSON.
런타임(fastapi/엔진) 의존이라 단위 테스트는 오케스트레이터에서 수행(통합 검증 대상).
"""

from __future__ import annotations

from fastapi import APIRouter, File, HTTPException, Query, UploadFile

from app.deps import get_openai_client, get_yolo_engine
from app.services.orchestrator import run_analysis
from app.services.preprocess import ImageDecodeError, ImageTooLargeError

router = APIRouter()


@router.post("/analyze")
async def analyze(  # pragma: no cover - 통합 검증 대상
    file: UploadFile = File(...),
    engine: str = Query("auto", pattern="^(auto|yolo)$"),
):
    data = await file.read()
    try:
        result = run_analysis(
            data,
            engine=engine,
            yolo=get_yolo_engine(),
            openai=get_openai_client() if engine == "auto" else None,
        )
    except ImageDecodeError:
        raise HTTPException(status_code=422, detail="invalid image")
    except ImageTooLargeError:
        raise HTTPException(status_code=413, detail="image too large (>10MB)")
    return result.model_dump()
