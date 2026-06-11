"""api↔ai 내부 서비스 인증 (D10) — apps/api ai-client.ts와 1:1 대칭.

토큰 포맷:
  body  = base64url(utf8(json(payload)))            # 패딩 없음
  sig   = base64url(hmac_sha256(secret, body))       # 패딩 없음
  token = f"{body}.{sig}"
payload = {iss:'api', aud:'ai', exp:<unix>, request_id:<str>}

검증은 수신한 body 문자열에 대해 HMAC을 재계산(상수시간 비교)하므로 TS/python 간
JSON 직렬화 차이와 무관하게 호환된다. backend-design §3.2/§3.8/D10.
"""

from __future__ import annotations

import base64
import hmac
import json
import time
from hashlib import sha256


class InternalAuthError(Exception):
    """내부 토큰 누락/변조/만료/불일치."""


def _b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64url_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def _sig(secret: str, body: str) -> str:
    return _b64url_encode(hmac.new(secret.encode("utf-8"), body.encode("ascii"), sha256).digest())


def sign_internal_bearer(
    secret: str,
    *,
    request_id: str,
    ttl_sec: int = 300,
    audience: str = "ai",
    now: float | None = None,
) -> str:
    issued = time.time() if now is None else now
    payload = {
        "iss": "api",
        "aud": audience,
        "exp": int(issued) + ttl_sec,
        "request_id": request_id,
    }
    body = _b64url_encode(json.dumps(payload).encode("utf-8"))
    return f"{body}.{_sig(secret, body)}"


def verify_internal_bearer(
    secret: str,
    token: str,
    *,
    audience: str = "ai",
    request_id: str | None = None,
    now: float | None = None,
) -> dict:
    current = time.time() if now is None else now
    parts = token.split(".")
    if len(parts) != 2 or not parts[0] or not parts[1]:
        raise InternalAuthError("malformed token")
    body, sig = parts
    if not hmac.compare_digest(sig, _sig(secret, body)):
        raise InternalAuthError("bad signature")
    try:
        payload = json.loads(_b64url_decode(body))
    except Exception as exc:  # noqa: BLE001
        raise InternalAuthError("bad payload") from exc
    if not isinstance(payload.get("exp"), int) or current > payload["exp"]:
        raise InternalAuthError("expired")
    if payload.get("aud") != audience:
        raise InternalAuthError("audience mismatch")
    if request_id is not None and payload.get("request_id") != request_id:
        raise InternalAuthError("request_id mismatch")
    return payload
