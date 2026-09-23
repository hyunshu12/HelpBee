"""외부 감염 라벨 데이터 정규화 — Stage-2(벌 단위 감염 분류기) 학습용.

두 CC BY 4.0 데이터셋을 한 행 스키마로 맞춘다:
    {source: str, image: Path, label: int, split: str,
     boxes: list[tuple[int, int, int, int]], varroa_visible: bool | None}
`image` 는 각 데이터셋 압축 해제 루트 기준 상대경로. label 1 = 감염, 0 = 건강.

VarroaDataset (Zenodo 4085044) — `gt.csv` (2026-09-23 원본으로 확인, 13,509행)
    한 줄 = `<split>/videos/<date>/<name>.png <label> [x1 y1 x2 y2]*` (공백 구분, 헤더 없음)
    - 이미지는 벌 1마리 크롭(160×280). 박스는 **응애** 위치 (크롭 좌표), 0개 이상.
    - label: 0 = 건강(9,562) / 1 = 감염(3,083) / 3 = 감염(864) → 1·3 을 1 로 합쳐 3,947 = README pos 수와 일치.
    - split: 경로 첫 세그먼트 train(8,225) / val(1,876) / test(3,408). `videos/<date>` 가 영상 단위 그룹.

EV2 (Zenodo 13771384) — `dataset.zip` 안의 `labels.txt` (2026-09-23 zip 목록·labels.txt 만 range 요청으로 확인)
    zip 구조: `dataset_free/*.png`, `dataset_infested/*.png` (5,170장), `labels.txt` (JSON Lines, 5,170줄)
    한 줄 = 한 프레임 = 벌 1마리:
        {"video": "varroa_infested/1_00953.MTS", "id": "frame_4", "varroa_visible": "yes"|"no",
         "coord_1": [x1, y1], "coord_2": [x2, y2]}
    - 박스는 **벌** 위치 (1920×1080 프레임 좌표), 항상 1개.
    - label: `video` 접두가 varroa_infested → 1 (3,882), varroa_free → 0 (1,288).
    - ⚠️ 폴더 ≠ 감염 라벨: 이미지 폴더는 `varroa_visible` 로 정해진다 (yes → dataset_infested/,
      no → dataset_free/). 감염됐지만 응애가 안 보이는 프레임 699장이 dataset_free/ 에 있으므로
      폴더명으로 라벨을 매기면 안 된다.
    - 파일명: `<video 파일명>_<id 에서 '_' 제거>.png` (예: 1_00953.MTS_frame4.png). 영상 32개.
    - split 은 "unsplit" — hold-out 은 manifest 단계(Task 5)에서 기록. 같은 영상의 연속 프레임은
      거의 동일하므로 영상(파일명의 `.MTS` 앞) 단위로 잘라야 누수가 없다.
"""
from __future__ import annotations

import json
from pathlib import Path

VARROA_ZENODO = "https://zenodo.org/records/4085044"
EV2_ZENODO = "https://zenodo.org/records/13771384"  # dataset.zip MD5 c626a1f198cf7d0f41eae9c2660b0985

_EV2_LABEL = {"varroa_infested": 1, "varroa_free": 0}
_EV2_VISIBLE = {"yes": True, "no": False}


def parse_varroa_gt(csv_path: Path) -> list[dict]:
    rows = []
    for line in Path(csv_path).read_text(encoding="utf-8").splitlines():
        t = line.split()
        if len(t) < 2:
            continue
        coords = list(map(int, t[2:]))
        if len(coords) % 4:
            raise ValueError(f"VarroaDataset 좌표 수가 4의 배수가 아님: {line!r}")
        boxes = [tuple(coords[i : i + 4]) for i in range(0, len(coords), 4)]
        rows.append({"source": "varroadataset", "image": Path(t[0]), "label": 1 if t[1] in ("1", "3") else 0,
                     "split": t[0].split("/")[0], "boxes": boxes, "varroa_visible": None})
    return rows


def parse_ev2(jsonl_path: Path) -> list[dict]:
    rows = []
    for line in Path(jsonl_path).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        d = json.loads(line)
        cls, video = d["video"].split("/", 1)
        visible = _EV2_VISIBLE[d["varroa_visible"]]
        folder = "dataset_infested" if visible else "dataset_free"
        (x1, y1), (x2, y2) = d["coord_1"], d["coord_2"]
        rows.append({"source": "ev2", "image": Path(folder, f"{video}_{d['id'].replace('_', '')}.png"),
                     "label": _EV2_LABEL[cls], "split": "unsplit", "boxes": [(x1, y1, x2, y2)],
                     "varroa_visible": visible})
    return rows
