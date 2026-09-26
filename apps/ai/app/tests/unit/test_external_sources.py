from pathlib import Path

from training.data.external_sources import parse_ev2, parse_varroa_gt


def test_varroa_gt_labels_1_and_3_positive(tmp_path: Path):
    p = tmp_path / "gt.csv"
    p.write_text("test/v/a.png 1 84 143 109 172 54 142 82 172\ntest/v/b.png 0\ntrain/v/c.png 3 92 115 133 149\n", encoding="utf-8")
    rows = parse_varroa_gt(p)
    assert [(r["label"], r["split"], len(r["boxes"])) for r in rows] == [(1, "test", 2), (0, "test", 0), (1, "train", 1)]
    assert rows[0]["boxes"] == [(84, 143, 109, 172), (54, 142, 82, 172)]
    assert rows[0]["source"] == "varroadataset" and rows[0]["varroa_visible"] is None


# EV2 실제 스키마 (Zenodo 13771384 dataset.zip 의 labels.txt, 2026-09-23 확인):
# 한 줄 = 한 프레임 = 벌 1마리. 감염 라벨은 video 접두(varroa_infested/varroa_free)에서,
# 이미지 폴더는 varroa_visible 에서 결정된다 — 감염이지만 응애가 안 보이는 프레임은 dataset_free/ 에 있다.
EV2_LINES = (
    '{"video": "varroa_infested/1_00953.MTS", "id": "frame_4", "varroa_visible": "yes", "coord_1": [702, 708], "coord_2": [1044, 969]}\n'
    '{"video": "varroa_infested/1_00953.MTS", "id": "frame_6", "varroa_visible": "no", "coord_1": [701, 634], "coord_2": [1126, 971]}\n'
    "\n"
    '{"video": "varroa_free/19_00974.MTS", "id": "frame_102", "varroa_visible": "no", "coord_1": [1, 2], "coord_2": [50, 60]}\n'
)


def test_ev2_label_from_video_prefix_and_visible_flag_kept(tmp_path: Path):
    p = tmp_path / "labels.txt"
    p.write_text(EV2_LINES, encoding="utf-8")
    rows = parse_ev2(p)
    assert [(r["label"], r["varroa_visible"]) for r in rows] == [(1, True), (1, False), (0, False)]
    assert rows[2]["boxes"] == [(1, 2, 50, 60)]
    assert all(r["source"] == "ev2" and r["split"] == "unsplit" for r in rows)


def test_ev2_image_path_follows_visible_flag_not_label(tmp_path: Path):
    p = tmp_path / "labels.txt"
    p.write_text(EV2_LINES, encoding="utf-8")
    images = [r["image"] for r in parse_ev2(p)]
    assert images == [
        Path("dataset_infested/1_00953.MTS_frame4.png"),
        Path("dataset_free/1_00953.MTS_frame6.png"),
        Path("dataset_free/19_00974.MTS_frame102.png"),
    ]


def test_ev2_box_normalized_when_dragged_backwards(tmp_path: Path):
    p = tmp_path / "labels.txt"
    p.write_text('{"video": "varroa_infested/2_00001.MTS", "id": "frame_1", "varroa_visible": "yes", '
                 '"coord_1": [1044, 969], "coord_2": [702, 708]}\n', encoding="utf-8")
    assert parse_ev2(p)[0]["boxes"] == [(702, 708, 1044, 969)]
