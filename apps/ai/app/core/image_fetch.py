"""이미지 fetch + SSRF 가드 (backend-design §3.8).

ai는 S3 자격증명/OpenAI 키 보유 고가치 타깃 → 임의 URL fetch 금지.
- scheme https only(기본), host allowlist, 해석된 IP가 전역(global)이 아니면 거부
  (사설/loopback/link-local/메타데이터 169.254.169.254 차단, DNS rebinding 대비).
- redirect 비허용.
"""

from __future__ import annotations

import ipaddress
import socket
from typing import Callable
from urllib.parse import urlparse


class UnsafeUrlError(Exception):
    """SSRF 가드 위반 또는 안전하지 않은 URL."""


def _default_resolve(host: str) -> list[str]:
    return [info[4][0] for info in socket.getaddrinfo(host, None)]


def assert_safe_url(
    url: str,
    *,
    allowlist_hosts: list[str],
    allow_http: bool = False,
    resolve: Callable[[str], list[str]] = _default_resolve,
) -> None:
    parsed = urlparse(url)
    scheme = (parsed.scheme or "").lower()
    allowed_schemes = ("http", "https") if allow_http else ("https",)
    if scheme not in allowed_schemes:
        raise UnsafeUrlError(f"scheme not allowed: {scheme}")
    host = parsed.hostname
    if not host:
        raise UnsafeUrlError("missing host")
    if not any(host == h or host.endswith("." + h) for h in allowlist_hosts):
        raise UnsafeUrlError(f"host not allowlisted: {host}")
    for ip in resolve(host):
        if not ipaddress.ip_address(ip).is_global:
            raise UnsafeUrlError(f"resolved to non-global ip: {ip}")


def fetch_image(  # pragma: no cover - 네트워크 통합 검증 대상
    url: str,
    *,
    allowlist_hosts: list[str],
    timeout: float = 10.0,
    max_bytes: int = 12 * 1024 * 1024,
    allow_http: bool = False,
) -> bytes:
    assert_safe_url(url, allowlist_hosts=allowlist_hosts, allow_http=allow_http)
    import httpx  # lazy

    with httpx.Client(timeout=timeout, follow_redirects=False) as client:
        resp = client.get(url)
        resp.raise_for_status()
        data = resp.content
    if len(data) > max_bytes:
        raise UnsafeUrlError(f"image exceeds {max_bytes} bytes")
    return data
