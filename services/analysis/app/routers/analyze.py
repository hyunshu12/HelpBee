from fastapi import APIRouter, Depends
from app.models.request import AnalyzeRequest
from app.models.response import AnalysisResponse
from app.services.analysis_service import AnalysisService

router = APIRouter(tags=["analysis"])


def get_analysis_service() -> AnalysisService:
    return AnalysisService()


@router.post("/", response_model=AnalysisResponse)
async def analyze_hive(
    body: AnalyzeRequest,
    service: AnalysisService = Depends(get_analysis_service),
):
    """벌통 이미지를 분석하여 바로아 응애 감염 진단 결과를 반환합니다."""
    return await service.analyze(body)
