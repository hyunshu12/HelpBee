# apps/ai/app/tests/unit/test_golden_holdout.py
from training.data.golden_holdout import select_golden
def test_select_golden_uses_json_category_not_yolo_labels():
    imgs = {}
    for c in ("001", "002", "003"):
        for i in range(60):
            imgs[f"/g/{c}/{i}.jpg"] = {"split": "golden", "colony": c, "device": "소비판촬영기" if i % 2 else "플레이트촬영기",
                                      "has_varroa_adult": i % 3 == 0, "n_adult": 3 if i % 4 else 0}
    sel = select_golden({"images": imgs}, n_varroa=30, n_normal=60, seed=1)
    assert len(sel["varroa"]) == 30 and len(sel["normal"]) == 60
    assert all(imgs[p]["has_varroa_adult"] for p in sel["varroa"])
    assert all((not imgs[p]["has_varroa_adult"]) and imgs[p]["n_adult"] > 0 for p in sel["normal"])
    assert len({imgs[p]["colony"] for p in sel["varroa"] + sel["normal"]}) >= 3


def test_main_missing_manifest_exits_2(tmp_path):
    from training.data.golden_holdout import main
    out = tmp_path / "golden.json"
    assert main(["--manifest", str(tmp_path / "nope.json"), "--output", str(out)]) == 2
    assert not out.exists()
