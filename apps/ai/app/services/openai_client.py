"""OpenAI Vision 폴백 클라이언트.

설계 근거: backend-design §3.5(의미축 정합 — LLM은 risk_score 자유생성 X,
infestation_rate만 추정), apps/ai/CLAUDE.md §7-2(structured output), §7-6(비용).

- usd_from_usage: usage 토큰 → USD (순수, 테스트).
- OpenAIVisionClient: 주입된 SDK client로 호출 → infestation_rate/confidence 파싱.
  실제 OpenAI 호출 없이 fake client로 단위 검증.
"""

from __future__ import annotations

import base64
import json
from dataclasses import dataclass, field

# USD per 1M tokens (gpt-4o-mini, 2024 기준 — 변경 시 회귀 게이트)
PRICING: dict[str, dict[str, float]] = {
    "gpt-4o-mini-2024-07-18": {"input": 0.15, "output": 0.60, "cached_input": 0.075},
    "gpt-4o-mini": {"input": 0.15, "output": 0.60, "cached_input": 0.075},
}

# 구조화 출력 스키마 — LLM은 infestation_rate(%)와 confidence만 반환.
# risk_score/tier는 우리 risk.yaml 매핑으로 산출(엔진 간 의미축 일치).
_JSON_SCHEMA = {
    "type": "json_schema",
    "json_schema": {
        "name": "varroa_infestation",
        "strict": True,
        "schema": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "infestation_rate": {"type": "number", "minimum": 0, "maximum": 100},
                "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            },
            "required": ["infestation_rate", "confidence"],
        },
    },
}


@dataclass
class OpenAIResult:
    infestation_rate: float  # % — risk.yaml 매핑 입력
    confidence: float
    cost_usd: float
    model_version: str
    prompt_version: str | None
    raw: dict = field(default_factory=dict)


def usd_from_usage(
    input_tokens: int,
    output_tokens: int,
    cached_tokens: int = 0,
    *,
    pricing: dict[str, float],
) -> float:
    return (
        input_tokens / 1_000_000 * pricing["input"]
        + output_tokens / 1_000_000 * pricing["output"]
        + cached_tokens / 1_000_000 * pricing.get("cached_input", pricing["input"])
    )


def _usage_tokens(usage) -> tuple[int, int, int]:
    """SDK usage 객체에서 (input, output, cached) 추출 (구/신 필드 모두 대응)."""
    inp = getattr(usage, "prompt_tokens", None)
    if inp is None:
        inp = getattr(usage, "input_tokens", 0)
    out = getattr(usage, "completion_tokens", None)
    if out is None:
        out = getattr(usage, "output_tokens", 0)
    cached = 0
    details = getattr(usage, "prompt_tokens_details", None)
    if details is not None:
        cached = getattr(details, "cached_tokens", 0) or 0
    return int(inp or 0), int(out or 0), int(cached or 0)


class OpenAIVisionClient:
    def __init__(
        self,
        client,
        *,
        model: str,
        prompt_version: str,
        system_prompt: str = "You are an apiculture expert assessing varroa mite infestation from a hive frame photo. Estimate the infestation rate (percentage of bees showing varroa infestation) and your confidence.",
    ) -> None:
        self._client = client
        self._model = model
        self._prompt_version = prompt_version
        self._system_prompt = system_prompt
        self._pricing = PRICING.get(model, {"input": 0.15, "output": 0.60, "cached_input": 0.075})

    def analyze(self, jpeg: bytes) -> OpenAIResult:
        b64 = base64.b64encode(jpeg).decode("ascii")
        messages = [
            {"role": "system", "content": self._system_prompt},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "이 벌통 사진의 응애 감염률(%)과 신뢰도를 추정하세요."},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{b64}"},
                    },
                ],
            },
        ]
        resp = self._client.chat.completions.create(
            model=self._model,
            messages=messages,
            response_format=_JSON_SCHEMA,
        )
        content = resp.choices[0].message.content
        parsed = json.loads(content)
        inp, out, cached = _usage_tokens(resp.usage)
        cost = usd_from_usage(inp, out, cached, pricing=self._pricing)
        return OpenAIResult(
            infestation_rate=float(parsed["infestation_rate"]),
            confidence=float(parsed["confidence"]),
            cost_usd=cost,
            model_version=self._model,
            prompt_version=self._prompt_version,
            raw={"usage": {"input": inp, "output": out, "cached": cached}},
        )
