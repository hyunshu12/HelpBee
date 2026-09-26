from app.core.config import load_settings


def test_two_stage_defaults(monkeypatch):
    for k in ("AI_ENGINE", "TWO_STAGE_MODEL_VERSION", "AI_INTERNAL_BUDGET_S", "TWO_STAGE_CACHE_DIR"):
        monkeypatch.delenv(k, raising=False)
    s = load_settings()
    assert s.ai_engine == "two-stage" and s.two_stage_model_version == "v0.2.0"
    assert s.ai_internal_budget_s == 80.0 and s.two_stage_cache_dir.endswith("helpbee/two-stage")


def test_two_stage_env_override(monkeypatch):
    monkeypatch.setenv("AI_ENGINE", "yolo-v1")
    monkeypatch.setenv("TWO_STAGE_MODEL_VERSION", "v0.2.1")
    s = load_settings()
    assert s.ai_engine == "yolo-v1" and s.two_stage_model_version == "v0.2.1"


def test_empty_cache_dir_uses_default(monkeypatch):
    monkeypatch.setenv("TWO_STAGE_CACHE_DIR", "")
    assert load_settings().two_stage_cache_dir.endswith("helpbee/two-stage")
