"""B6 internal_auth — apps/api ai-client.ts의 HMAC bearer를 ai측에서 검증.

토큰 포맷은 ai-client.ts(signInternalBearer)와 1:1 대칭이어야 한다:
  body = base64url(utf8(json(payload)))  (패딩 없음)
  sig  = base64url(hmac_sha256(secret, body))  (패딩 없음)
  token = f"{body}.{sig}"
"""

import time

import pytest

from app.core.internal_auth import (
    InternalAuthError,
    sign_internal_bearer,
    verify_internal_bearer,
)

SECRET = "h" * 32


def test_roundtrip():
    t = sign_internal_bearer(SECRET, request_id="req-9", ttl_sec=300)
    p = verify_internal_bearer(SECRET, t)
    assert p["request_id"] == "req-9"
    assert p["aud"] == "ai"
    assert p["iss"] == "api"
    assert p["exp"] > int(time.time())


def test_rejects_tampered():
    t = sign_internal_bearer(SECRET, request_id="r")
    with pytest.raises(InternalAuthError):
        verify_internal_bearer(SECRET, t + "x")


def test_rejects_wrong_secret():
    t = sign_internal_bearer(SECRET, request_id="r")
    with pytest.raises(InternalAuthError):
        verify_internal_bearer("o" * 32, t)


def test_rejects_expired():
    t = sign_internal_bearer(SECRET, request_id="r", ttl_sec=-10)
    with pytest.raises(InternalAuthError):
        verify_internal_bearer(SECRET, t)


def test_rejects_aud_mismatch():
    t = sign_internal_bearer(SECRET, request_id="r", audience="web")
    with pytest.raises(InternalAuthError):
        verify_internal_bearer(SECRET, t)  # default aud="ai"


def test_rejects_request_id_mismatch():
    t = sign_internal_bearer(SECRET, request_id="r1")
    with pytest.raises(InternalAuthError):
        verify_internal_bearer(SECRET, t, request_id="r2")


def test_rejects_malformed():
    with pytest.raises(InternalAuthError):
        verify_internal_bearer(SECRET, "no-dot-here")
    with pytest.raises(InternalAuthError):
        verify_internal_bearer(SECRET, "a.b.c")
