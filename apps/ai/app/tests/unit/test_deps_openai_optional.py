"""get_openai_client — OpenAI를 못 쓰는 상태에서 raise 하지 않고 None 을 준다.

회귀 배경: 예전에는 키/패키지가 없으면 `os.environ[...]` KeyError 나
ModuleNotFoundError 가 라우터까지 올라가 engine=auto 요청이 500 으로 죽었다.
apps/api 는 그걸 `ai_unavailable` 로 저장하므로 **유료 사용자의 분석이 전부 실패**했다.
None 을 주면 run_analysis 가 `fallback_allowed=False` 로 YOLO 단독 처리한다.
"""

from __future__ import annotations

import builtins

import pytest

from app import deps


@pytest.fixture(autouse=True)
def _clear_cache():
    deps.get_openai_client.cache_clear()
    yield
    deps.get_openai_client.cache_clear()


def test_returns_none_without_api_key(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    assert deps.get_openai_client() is None


def test_returns_none_when_package_missing(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")

    real_import = builtins.__import__

    def _no_openai(name, *args, **kwargs):
        if name == "openai":
            raise ModuleNotFoundError("No module named 'openai'")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", _no_openai)
    assert deps.get_openai_client() is None


def test_empty_api_key_is_treated_as_unset(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "")
    assert deps.get_openai_client() is None
