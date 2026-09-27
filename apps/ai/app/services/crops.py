"""Stage-2 크롭 규칙 — 학습(training/data/make_crops.py)과 서빙(two_stage_engine)의 단일 소스.

서빙 Docker 이미지는 `app/` + `training/configs` 만 담으므로 규칙은 app 쪽에 두고
training 이 이를 재수출한다(training → app 의존은 vdi.py 와 같은 방향).
"""

from __future__ import annotations

import numpy as np


def normalize_box(box) -> tuple:
    """(x1, y1, x2, y2) 좌표 순서 정규화 — 라벨러가 어느 방향으로 끌었든 min/max."""
    x1, y1, x2, y2 = box
    return (min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2))


def crop_pad(img, box, margin=0.10, size=224):
    """박스 + margin 크롭 → 긴 변을 size 로 축소(종횡비 유지) 후 검정 패딩. (out, native) 반환."""
    import cv2

    H, W = img.shape[:2]
    x1, y1, x2, y2 = normalize_box(box)
    w, h = x2 - x1, y2 - y1
    x1, y1 = max(0, int(x1 - w * margin)), max(0, int(y1 - h * margin))
    x2, y2 = min(W, int(x2 + w * margin)), min(H, int(y2 + h * margin))
    native = img[y1:y2, x1:x2]
    if native.shape[0] == 0 or native.shape[1] == 0:
        raise ValueError(f"빈 크롭: box={box} image={W}x{H}")
    s = size / max(native.shape[:2])
    r = cv2.resize(native, (max(1, int(native.shape[1] * s)), max(1, int(native.shape[0] * s))),
                   interpolation=cv2.INTER_AREA)
    out = np.zeros((size, size, 3), np.uint8)
    oy, ox = (size - r.shape[0]) // 2, (size - r.shape[1]) // 2
    out[oy:oy + r.shape[0], ox:ox + r.shape[1]] = r
    return out, native
