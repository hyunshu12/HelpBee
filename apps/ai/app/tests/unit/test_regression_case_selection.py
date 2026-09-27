"""회귀 fixture v2 케이스 선정 규칙 (training.data.make_regression_fixtures.select_cases).

합성 DataFrame 으로 규칙만 검증한다 — 모델/데이터셋 불필요.
"""

from __future__ import annotations

import pandas as pd
import pytest

from training.data.make_regression_fixtures import CASES, CASE_QUOTA, select_cases


def _row(path, *, source="sample", folder="성충_응애", bees=40, inf=2, vdi="5.0", tier="elevated", ok=True):
    return {
        "path": path,
        "source": source,
        "class_folder": folder,
        "bee_total": bees,
        "bee_infested": inf,
        "vdi_display": vdi if bees > 0 and ok else None,
        "tier": tier if bees > 0 and ok else "insufficient",
        "quality_ok": ok,
    }


@pytest.fixture()
def df() -> pd.DataFrame:
    rows = []
    # 숨은 응애 후보: 성충_응애 + infested 0
    rows += [_row(f"S/a{i}.jpg", inf=0, vdi="0.0", tier="low", bees=30 + i) for i in range(6)]
    # 경계 후보: 3.0 / 10.0 근처 + 먼 값
    for i, v in enumerate(["2.8", "3.2", "9.7", "10.4", "6.5", "20.0", "0.9"]):
        t = "low" if float(v) < 3 else ("elevated" if float(v) < 10 else "high")
        rows.append(_row(f"S/b{i}.jpg", folder="성충_날개불구바이러스감염증", vdi=v, tier=t, bees=50))
    # 저벌수: 1~5
    rows += [_row(f"S/c{i}.jpg", folder="유충_정상", bees=1 + i % 5, inf=0, vdi="0.0", tier="low") for i in range(5)]
    # 정상: 성충_정상 + infested 0
    rows += [_row(f"S/d{i}.jpg", folder="성충_정상", bees=60 + i, inf=0, vdi="0.0", tier="low") for i in range(5)]
    # 밀집: 큰 bee_total
    rows += [_row(f"S/e{i}.jpg", folder="유충_부저병", bees=300 + i, inf=0, vdi="0.0", tier="low") for i in range(5)]
    # 합성 0마리 / 블러
    rows += [_row(f"D/z{i}.jpg", source="zero_bees", folder="synthetic", bees=0, inf=0) for i in range(3)]
    rows += [_row(f"D/bl{i}.jpg", source="blur", folder="성충_정상", bees=10, inf=0, ok=False) for i in range(3)]
    return pd.DataFrame(rows)


def test_every_case_gets_quota(df):
    out = select_cases(df)
    counts = out["case"].value_counts().to_dict()
    for case in CASES:
        assert counts.get(case, 0) >= 3, (case, counts)
        assert counts[case] == min(CASE_QUOTA[case], counts[case])
    assert 24 <= len(out) <= 30
    assert out["path"].is_unique  # 한 이미지는 한 케이스에만


def test_case_rules(df):
    out = select_cases(df).set_index("path")
    by = {c: out[out["case"] == c] for c in CASES}
    assert (by["zero_bees"]["bee_total"] == 0).all() and (by["zero_bees"]["source"] == "zero_bees").all()
    assert (~by["blur"]["quality_ok"]).all() and (by["blur"]["source"] == "blur").all()
    v = by["varroa_visible_no"]
    assert (v["class_folder"] == "성충_응애").all() and (v["bee_infested"] == 0).all()
    h = by["healthy"]
    assert (h["class_folder"] == "성충_정상").all() and (h["bee_infested"] == 0).all()
    assert by["low_count"]["bee_total"].between(1, 5).all()
    # 경계: 가장 가까운 것부터 — 2.8/3.2/9.7/10.4 가 먼저
    assert set(by["boundary"]["vdi_display"]) >= {"2.8", "3.2", "9.7"}
    assert "20.0" not in set(by["boundary"]["vdi_display"])
    # 밀집: 최대 bee_total
    assert by["dense"]["bee_total"].min() >= 302


def test_deterministic(df):
    a = select_cases(df)
    b = select_cases(df.sample(frac=1.0, random_state=7))  # 입력 순서 무관
    pd.testing.assert_frame_equal(a.reset_index(drop=True), b.reset_index(drop=True))


def test_boundary_needs_valid_vdi(df):
    df2 = df.copy()
    out = select_cases(df2)
    assert out[out["case"] == "boundary"]["vdi_display"].notna().all()


def test_nfd_folder_names_match(df):
    """macOS 파일시스템은 한글 경로를 NFD 로 돌려준다 — 폴더 규칙이 NFC 리터럴과 맞아야 한다."""
    import unicodedata

    nfd = df.copy()
    nfd["class_folder"] = nfd["class_folder"].map(lambda s: unicodedata.normalize("NFD", s))
    counts = select_cases(nfd)["case"].value_counts().to_dict()
    assert counts.get("healthy", 0) >= 3 and counts.get("varroa_visible_no", 0) >= 3, counts
