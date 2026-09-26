"""POST /aggregate — N장 합산은 카운트 합산(퍼센트 평균 아님), vdi.aggregate 단일 소스."""
import pytest
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.internal_auth import sign_internal_bearer
from app.main import app
from app.routers import aggregate as agg_router
from app.services.vdi import VdiConfig

SECRET = "s" * 32
CFG = VdiConfig(tau=0.64, tpr=0.516, fpr=0.00246, corrected=True)


@pytest.fixture
def client_with_internal_token(monkeypatch):
    monkeypatch.setattr(settings, "ai_internal_hmac_secret", SECRET)
    app.dependency_overrides[agg_router.get_vdi_config] = lambda: CFG
    token = sign_internal_bearer(SECRET, request_id="req-agg")
    client = TestClient(app, headers={"authorization": f"Bearer {token}", "x-request-id": "req-agg"})
    yield client
    app.dependency_overrides.clear()


def test_aggregate_sums_counts(client_with_internal_token):
    r = client_with_internal_token.post(
        "/aggregate",
        json={"counts": [{"bee_infested": 1, "bee_total": 40}, {"bee_infested": 9, "bee_total": 900}]},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["bee_total"] == 940 and body["bee_infested"] == 10
    assert body["tier"] == "low"
    assert body["corrected"] is True
    assert body["vdi_raw"] == pytest.approx(10 / 940 * 100)
    assert len(body["sampling_ci95"]) == 2
    assert set(body) >= {"vdi", "vdi_display", "vdi_raw", "sampling_ci95", "bee_total", "bee_infested", "tier", "corrected"}


def test_aggregate_quality_flag_forces_insufficient(client_with_internal_token):
    r = client_with_internal_token.post(
        "/aggregate", json={"counts": [{"bee_infested": 5, "bee_total": 50}], "quality_ok": False}
    )
    assert r.status_code == 200 and r.json()["tier"] == "insufficient"


def test_aggregate_rejects_empty(client_with_internal_token):
    assert client_with_internal_token.post("/aggregate", json={"counts": []}).status_code == 422


def test_aggregate_rejects_too_many_and_invalid_counts(client_with_internal_token):
    many = [{"bee_infested": 0, "bee_total": 1}] * 51
    assert client_with_internal_token.post("/aggregate", json={"counts": many}).status_code == 422
    bad = [{"bee_infested": 5, "bee_total": 3}]
    assert client_with_internal_token.post("/aggregate", json={"counts": bad}).status_code == 422
    neg = [{"bee_infested": -1, "bee_total": 3}]
    assert client_with_internal_token.post("/aggregate", json={"counts": neg}).status_code == 422


def test_aggregate_requires_internal_token(monkeypatch):
    monkeypatch.setattr(settings, "ai_internal_hmac_secret", SECRET)
    r = TestClient(app).post("/aggregate", json={"counts": [{"bee_infested": 1, "bee_total": 40}]})
    assert r.status_code == 401
