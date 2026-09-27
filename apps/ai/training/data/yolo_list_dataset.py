"""manifest(txt 이미지 목록) 모드에서 라벨을 <output>/labels/all/<label stem>.txt 에서 찾도록 ultralytics 패치.

Ultralytics 기본 img2label_paths 는 이미지 경로의 `images` 세그먼트를 `labels` 로 치환한다.
manifest 모드(aihub_to_yolo.py --manifest)는 이미지를 복사하지 않고 원본 절대경로를 쓰므로
그 치환이 성립하지 않는다 → 라벨 경로를 직접 계산하도록 교체한다.

라벨 stem 규칙 (결정): aihub_to_yolo._unique_filename 과 동일하게 `<이미지 부모폴더명>_<이미지 stem>`.
71667 은 라벨 JSON 과 이미지가 미러 구조(02.라벨링데이터/.../NNN/X.json ↔ 01.원천데이터/.../NNN/X.jpg)라
JSON 부모폴더명 == 이미지 부모폴더명 이므로, 리스트 파일에는 **원본 이미지 절대경로 그대로**를 두고
라벨 파일명은 이미지 경로에서 계산한다 (Ultralytics 가 이미지를 읽어야 하므로 리스트는 이미지 경로여야 한다).
"""
from __future__ import annotations

from pathlib import Path


def label_path_for(img_path: str | Path, label_root: Path) -> Path:
    p = Path(img_path)
    return Path(label_root) / f"{p.parent.name}_{p.stem}.txt"


def patch_label_lookup(label_root: Path) -> None:
    """ultralytics.data.utils / .dataset 의 img2label_paths 를 교체.

    dataset.py 는 `from .utils import img2label_paths` 로 이름을 바인딩하므로 두 모듈 모두 패치해야 한다.
    ultralytics 는 함수 안에서 lazy import (학습 박스 외 환경에서 모듈 import 가능하도록).
    """
    from ultralytics.data import dataset, utils  # type: ignore

    root = Path(label_root)

    def img2label_paths(img_paths):
        return [str(label_path_for(p, root)) for p in img_paths]

    utils.img2label_paths = img2label_paths
    dataset.img2label_paths = img2label_paths
