# apps/ai/app/tests/unit/test_train_overrides.py
import sys
import types
from pathlib import Path

from training.train import apply_overrides, dump_resolved


def test_set_overrides_parse_types():
    cfg = {"epochs": 100, "lr0": 0.001, "amp": True, "name": "x"}
    out = apply_overrides(cfg, ["epochs=5", "lr0=3e-4", "amp=false", "name=v0.2.0-s1A", "scale=0.15"])
    assert out == {"epochs": 5, "lr0": 3e-4, "amp": False, "name": "v0.2.0-s1A", "scale": 0.15}
    assert cfg["epochs"] == 100  # 원본 불변


def test_dump_resolved_writes_json(tmp_path):
    p = dump_resolved({"a": 1}, tmp_path)
    assert p.name == "resolved_config.json" and '"a": 1' in p.read_text(encoding="utf-8")


def test_stage1_yaml_loads():
    import yaml

    root = Path(__file__).resolve().parents[3]
    cfg = yaml.safe_load((root / "training/configs/stage1.yaml").read_text(encoding="utf-8"))
    assert cfg["imgsz"] == 1024 and cfg["scale"] == 0.85 and cfg["data"] == "training/lists/stage1_all.yaml"


def test_patch_label_lookup_uses_parent_prefixed_stem(tmp_path, monkeypatch):
    """aihub_to_yolo._unique_filename 규칙(<부모폴더>_<stem>.txt)과 일치해야 한다."""
    from training.data.aihub_to_yolo import _unique_filename
    from training.data.yolo_list_dataset import label_path_for, patch_label_lookup

    img = tmp_path / "01.원천데이터/성충/성충_응애/044/C_002_007_x.jpg"
    json_p = tmp_path / "02.라벨링데이터/성충/성충_응애/044/C_002_007_x.json"
    expected_name = Path(_unique_filename(json_p, img.name)).with_suffix(".txt").name
    root = tmp_path / "labels/all"
    assert label_path_for(img, root) == root / expected_name

    utils = types.ModuleType("ultralytics.data.utils")
    dataset = types.ModuleType("ultralytics.data.dataset")
    utils.img2label_paths = dataset.img2label_paths = lambda ps: ["orig"]
    pkg = types.ModuleType("ultralytics")
    data = types.ModuleType("ultralytics.data")
    data.utils, data.dataset = utils, dataset
    pkg.data = data
    for name, mod in {"ultralytics": pkg, "ultralytics.data": data,
                      "ultralytics.data.utils": utils, "ultralytics.data.dataset": dataset}.items():
        monkeypatch.setitem(sys.modules, name, mod)
    patch_label_lookup(root)
    assert utils.img2label_paths([str(img)]) == [str(root / expected_name)]
    assert dataset.img2label_paths([str(img)]) == [str(root / expected_name)]


def test_apply_fold_suffixes_run_name_unless_name_given():
    from training.train import apply_fold

    cfg = {"name": "v0.2.0-stage1", "data": "x.yaml"}
    assert apply_fold(cfg, None, False) == cfg
    for f in ("A", "B", "all"):
        out = apply_fold(cfg, f, name_given=False)
        assert out["name"] == f"v0.2.0-stage1{f}" and out["data"] == f"training/lists/stage1_{f}.yaml"
    assert apply_fold({**cfg, "name": "custom"}, "A", name_given=True)["name"] == "custom"
    assert cfg["name"] == "v0.2.0-stage1"  # 원본 불변
