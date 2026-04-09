from pydantic import BaseModel
from typing import Literal
from datetime import datetime


class AnalysisResponse(BaseModel):
    analysis_id: str
    hive_id: str
    risk_level: Literal["low", "medium", "high", "critical"]
    varroa_detected: bool
    infestation_rate: float
    confidence_score: float
    recommendations: list[str]
    analyzed_at: datetime
