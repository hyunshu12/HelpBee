"""B6 image_fetch — SSRF 가드(scheme/host allowlist/사설·메타데이터 IP 거부).

실제 네트워크 fetch는 통합 검증 대상. 여기선 assert_safe_url의 가드 로직을
주입된 resolver로 단위 검증한다.
"""

import pytest

from app.core.image_fetch import UnsafeUrlError, assert_safe_url

ALLOW = ["s3.ap-northeast-2.amazonaws.com", "cdn.helpbee.kr"]


def resolver(mapping):
    return lambda host: mapping.get(host, ["8.8.8.8"])


def test_allows_allowlisted_host_with_global_ip():
    assert_safe_url(
        "https://helpbee-images.s3.ap-northeast-2.amazonaws.com/k.jpg",
        allowlist_hosts=ALLOW,
        resolve=resolver({"helpbee-images.s3.ap-northeast-2.amazonaws.com": ["52.219.1.1"]}),
    )


def test_rejects_non_allowlisted_host():
    with pytest.raises(UnsafeUrlError):
        assert_safe_url(
            "https://evil.example.com/k.jpg",
            allowlist_hosts=ALLOW,
            resolve=resolver({"evil.example.com": ["1.1.1.1"]}),
        )


def test_rejects_http_scheme_by_default():
    with pytest.raises(UnsafeUrlError):
        assert_safe_url(
            "http://cdn.helpbee.kr/k.jpg",
            allowlist_hosts=ALLOW,
            resolve=resolver({"cdn.helpbee.kr": ["1.1.1.1"]}),
        )


def test_rejects_private_resolved_ip():
    with pytest.raises(UnsafeUrlError):
        assert_safe_url(
            "https://cdn.helpbee.kr/k.jpg",
            allowlist_hosts=ALLOW,
            resolve=resolver({"cdn.helpbee.kr": ["192.168.0.5"]}),  # DNS rebinding
        )


def test_rejects_metadata_ip():
    with pytest.raises(UnsafeUrlError):
        assert_safe_url(
            "https://cdn.helpbee.kr/k.jpg",
            allowlist_hosts=ALLOW,
            resolve=resolver({"cdn.helpbee.kr": ["169.254.169.254"]}),
        )


def test_rejects_loopback_ip():
    with pytest.raises(UnsafeUrlError):
        assert_safe_url(
            "https://cdn.helpbee.kr/k.jpg",
            allowlist_hosts=ALLOW,
            resolve=resolver({"cdn.helpbee.kr": ["127.0.0.1"]}),
        )
