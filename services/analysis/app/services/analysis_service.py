import uuid
import json
from datetime import datetime, timezone

from openai import AsyncOpenAI
from app.models.request import AnalyzeRequest
from app.models.response import AnalysisResponse
from app.prompts.varroa_analysis import VARROA_ANALYSIS_PROMPT


class AnalysisService:
    def __init__(self):
        self.client = AsyncOpenAI()

    async def analyze(self, body: AnalyzeRequest) -> AnalysisResponse:
        response = await self.client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": VARROA_ANALYSIS_PROMPT},
                        {
                            "type": "image_url",
                            "image_url": {"url": str(body.image_url), "detail": "high"},
                        },
                    ],
                }
            ],
            response_format={"type": "json_object"},
        )

        result = json.loads(response.choices[0].message.content)

        return AnalysisResponse(
            analysis_id=str(uuid.uuid4()),
            hive_id=body.hive_id,
            risk_level=result["risk_level"],
            varroa_detected=result["varroa_detected"],
            infestation_rate=result["infestation_rate"],
            confidence_score=result["confidence_score"],
            recommendations=result["recommendations"],
            analyzed_at=datetime.now(timezone.utc),
        )
