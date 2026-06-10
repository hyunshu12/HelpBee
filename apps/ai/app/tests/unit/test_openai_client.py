"""B4 openai_client — usage→USD 비용 + 구조화 응답 파싱 (주입된 fake 클라이언트).

실제 OpenAI 호출 없이 SDK 응답 형태만 흉내내 파싱/비용을 검증.
"""

import json
from types import SimpleNamespace

from app.services.openai_client import (
    OpenAIResult,
    OpenAIVisionClient,
    usd_from_usage,
)


def test_usd_from_usage():
    pricing = {"input": 0.15, "output": 0.60, "cached_input": 0.075}
    cost = usd_from_usage(1_000_000, 500_000, 0, pricing=pricing)
    assert abs(cost - (0.15 + 0.30)) < 1e-9


def test_usd_from_usage_with_cached():
    pricing = {"input": 0.15, "output": 0.60, "cached_input": 0.075}
    cost = usd_from_usage(0, 0, 1_000_000, pricing=pricing)
    assert abs(cost - 0.075) < 1e-9


class _FakeResp:
    def __init__(self, content, usage):
        self.choices = [SimpleNamespace(message=SimpleNamespace(content=content))]
        self.usage = usage


class _FakeClient:
    """openai SDK의 client.chat.completions.create 형태만 흉내."""

    def __init__(self, content, usage):
        self.last_kwargs = None
        self.chat = SimpleNamespace(
            completions=SimpleNamespace(create=self._create)
        )
        self._content = content
        self._usage = usage

    def _create(self, **kwargs):
        self.last_kwargs = kwargs
        return _FakeResp(self._content, self._usage)


def test_analyze_parses_infestation_and_cost():
    content = json.dumps({"infestation_rate": 12.5, "confidence": 0.8})
    usage = SimpleNamespace(prompt_tokens=1000, completion_tokens=200, prompt_tokens_details=None)
    client = _FakeClient(content, usage)
    c = OpenAIVisionClient(client, model="gpt-4o-mini-2024-07-18", prompt_version="varroa@1.0")
    res = c.analyze(b"\xff\xd8jpegbytes")
    assert isinstance(res, OpenAIResult)
    assert res.infestation_rate == 12.5
    assert res.confidence == 0.8
    assert res.cost_usd > 0
    assert res.model_version == "gpt-4o-mini-2024-07-18"
    assert res.prompt_version == "varroa@1.0"


def test_analyze_sends_image_and_json_schema():
    content = json.dumps({"infestation_rate": 0.0, "confidence": 0.5})
    usage = SimpleNamespace(prompt_tokens=10, completion_tokens=10)
    client = _FakeClient(content, usage)
    c = OpenAIVisionClient(client, model="gpt-4o-mini-2024-07-18", prompt_version="varroa@1.0")
    c.analyze(b"\xff\xd8abc")
    kw = client.last_kwargs
    assert kw["model"] == "gpt-4o-mini-2024-07-18"
    # 구조화 출력(json_schema) 강제
    assert kw["response_format"]["type"] == "json_schema"
    # 이미지가 메시지에 base64로 포함
    dumped = json.dumps(kw["messages"])
    assert "data:image/jpeg;base64," in dumped
