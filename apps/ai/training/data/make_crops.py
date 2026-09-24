"""Stage-2(벌 단위 감염 분류기) 크롭 데이터셋 — out-of-fold Stage-1 예측 박스 기반.

Usage (apps/ai 에서, 학습 박스):
    python -m training.data.make_crops --manifest training/split_manifest.json \\
        --weights-A training/runs/yolo/v0.2.0-stage1A/weights/best.pt \\
        --weights-B training/runs/yolo/v0.2.0-stage1B/weights/best.pt \\
        --weights-all training/runs/yolo/v0.2.0-stage1all/weights/best.pt \\
        --out training/crops [--external-varroa <root>] [--external-ev2 <root>]

71667: Stage-1 예측 박스를 GT(legacy3 파싱, 원래 cat71667 사용)와 IoU≥0.5 로 1:1 매칭하고, 매칭된
GT 카테고리로 라벨을 붙인다(label_for). 서빙 때 Stage-2 는 Stage-1 박스를 받으므로 학습 크롭도
GT 박스가 아니라 예측 박스로 자른다. 누수 방지: train/val 이미지는 **자기 colony 가 학습에 쓰이지
않은** fold 모델로 예측한다(fold A colony → weights-B, fold B → weights-A). golden/cal_a/cal_b 는
어떤 fold 학습에도 안 들어갔으므로 weights-all. dropped_dup 은 건너뛴다.

외부(Task 4): VarroaDataset·EV2 모두 이미 벌 1마리 크롭(spec §2) → 이미지 전체를 크롭 박스로, 같은
crop_pad_224. EV2 의 프레임 좌표 벌 박스는 `ext_box` 열에 메타로만 남긴다(최종 리뷰 I1 — 이전 Task 8 판정
'boxes[0] 로 자름' 정정; 8b 에서 stats.json `external_ev2.image_sizes` 로 실제 크기 확인).
EV2 감염 영상의 응애 안 보이는 프레임(label 1 & varroa_visible False)은 제외(I2). split 은 VarroaDataset
자체 split, EV2 는 split_external(영상 단위 holdout).

산출물 (<out>, gitignored): {split}/{label}/*.png, crops.csv, stats.json.
crops.csv `source` 는 71667 이면 manifest 태그(`71667-val`/`71667-train`) 그대로 — 소비자는
`make_split_manifest.is_71667` 로 판정한다. stats.json `by_source_split` = {"<source>/<split>/<label>": n}.
stats.json 의 match_rate = 매칭된 성충 GT(cat 4·5·6) / 전체 성충 GT — 50% 미만이면 warning
(Stage-1 이 GT 를 놓치면 양성 크롭이 조용히 사라진다). manifest 에서 `n_adult == 0`(유충 전용, 71667 의
~70%)인 이미지는 JSON 을 열거나 예측하기 전에 건너뛰고 stats.json `skipped_no_adult` 로 센다.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

import numpy as np

from training.data.aihub_to_yolo import IMAGE_DIR_NAME, LABEL_DIR_NAME, parse_annotations
from training.make_fold_lists import colony_fold

CSV_COLUMNS = ("path", "label", "source", "colony", "device", "split", "native_w", "native_h", "cat71667",
               "image", "varroa_visible", "ext_box")
ADULT_CATS = (4, 5, 6)
PRED_KW = {"conf": 0.15, "imgsz": 1024, "max_det": 1500}


def iou(a, b):
    x1, y1, x2, y2 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    inter = max(0, x2 - x1) * max(0, y2 - y1)
    ua = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / ua if ua else 0.0


def match_predictions(preds, gts, iou_thr=0.5):
    """예측 박스 순서대로 아직 안 쓴 GT 중 IoU 최대와 greedy 1:1 매칭 → [(pred_box, cat)]."""
    used, out = set(), []
    for p in preds:
        best, bi = 0.0, -1
        for k, (_cat, g) in enumerate(gts):
            if k in used:
                continue
            v = iou(p, g)
            if v > best:
                best, bi = v, k
        if best >= iou_thr:
            used.add(bi)
            out.append((p, gts[bi][0]))
    return out


def label_for(cat: int, image_has_varroa: bool):
    if cat == 5:
        return 1
    if cat == 4:
        return None if image_has_varroa else 0  # 감염 이미지 내 '정상' 라벨은 불확실 → 제외
    return None  # 6 DWV 및 유충(0~3) 제외


def crop_pad_224(img, box, margin=0.10, size=224):
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


def write_stats(out_dir, matched, total, extra: dict | None = None):
    rate = matched / max(1, total)
    p = Path(out_dir) / "stats.json"
    p.write_text(json.dumps({"matched": matched, "total": total, "match_rate": rate, "warning": rate < 0.5,
                             **(extra or {})}, ensure_ascii=False, indent=2), encoding="utf-8")
    return p


def model_key_for(split: str, colony: str) -> str | None:
    """out-of-fold 예측 모델 키: train/val → 반대 fold, golden/cal → all, 그 외(dropped_dup) → None."""
    if split in ("train", "val"):
        return {"A": "B", "B": "A"}[colony_fold(colony)]
    if split in ("golden", "cal_a", "cal_b"):
        return "all"
    return None


def label_json_for(image: Path) -> Path:
    """01.원천데이터/.../X.jpg → 02.라벨링데이터/.../X.json (_resolve_image_path 의 역)."""
    parts = list(Path(image).parts)
    parts[parts.index(IMAGE_DIR_NAME)] = LABEL_DIR_NAME
    return Path(*parts).with_suffix(".json")


def normalize_box(box) -> tuple:
    """(x1, y1, x2, y2) 좌표 순서 정규화 — 라벨러가 어느 방향으로 끌었든 min/max."""
    x1, y1, x2, y2 = box
    return (min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2))


def external_crop_box(row: dict, shape) -> tuple:
    """외부 소스 크롭 박스 = **이미지 전체**. VarroaDataset·EV2 모두 이미 벌 1마리 크롭(spec §2)이다.
    VarroaDataset boxes 는 응애 위치, EV2 boxes[0] 은 원 프레임(1920×1080) 좌표의 벌 박스 — 둘 다
    크롭 PNG 좌표가 아니므로 자르는 데 쓰지 않는다(EV2 박스는 crops.csv `ext_box` 메타로만 남김)."""
    return (0, 0, shape[1], shape[0])


def include_external(row: dict) -> bool:
    """Stage-2 는 **보이는 응애** 분류기(VDI). EV2 감염 영상인데 응애가 안 보이는 프레임
    (label 1 & varroa_visible False, 699장)은 양성도 음성도 아니므로 제외한다."""
    return not (row["label"] == 1 and row.get("varroa_visible") is False)


def ext_box_meta(row: dict) -> str:
    """EV2 프레임 좌표 벌 박스(정규화) → 'x1 y1 x2 y2'. VarroaDataset(응애 박스) 은 빈 문자열."""
    if row["source"] != "ev2" or not row.get("boxes"):
        return ""
    return " ".join(str(v) for v in normalize_box(row["boxes"][0]))


def row_71667(rel: str, label: int, meta: dict, cat: int, image: str, nw: int, nh: int) -> list:
    """71667 크롭 CSV 행. `source` 는 manifest 태그(`71667-val` 등) 그대로 — 소비자는 is_71667 로 판정."""
    return [rel, label, meta.get("source", "71667"), meta.get("colony", ""), meta.get("device", ""),
            meta["split"], nw, nh, cat, image, "", ""]


def row_external(rel: str, r: dict, split: str, nw: int, nh: int) -> list:
    vis = "" if r["varroa_visible"] is None else str(r["varroa_visible"]).lower()
    return [rel, r["label"], r["source"], "", "", split, nw, nh, "", Path(r["image"]).as_posix(), vis,
            ext_box_meta(r)]


def count_crop(counter: dict, source: str, split: str, label: int) -> None:
    """stats.json `by_source_split` — {"71667/cal_a/1": n, ...} (71667 태그는 source_group 으로 합침)."""
    from training.data.make_split_manifest import source_group

    k = f"{source_group(source)}/{split}/{label}"
    counter[k] = counter.get(k, 0) + 1


# ---------- CLI (학습 박스 전용: cv2 + ultralytics 필요) ----------

def _imread(path: Path):
    import cv2  # cv2.imread 는 Windows 에서 비ASCII(한국어) 경로를 못 읽음 → fromfile+imdecode
    return cv2.imdecode(np.fromfile(str(path), np.uint8), cv2.IMREAD_COLOR)


def _imwrite(path: Path, img) -> None:
    import cv2
    path.parent.mkdir(parents=True, exist_ok=True)
    ok, buf = cv2.imencode(".png", img)
    if not ok:
        raise RuntimeError(f"PNG 인코딩 실패: {path}")
    buf.tofile(str(path))


def _crop_name(image: str, i: int) -> str:
    return f"{hashlib.sha1(image.encode('utf-8')).hexdigest()[:8]}_{Path(image).stem}_{i:03d}.png"


def _save(out: Path, img, box, split: str, label: int, image_key: str, i: int) -> tuple[str, tuple]:
    crop, native = crop_pad_224(img, box)
    rel = Path(split, str(label), _crop_name(image_key, i))
    _imwrite(out / rel, crop)
    return rel.as_posix(), native.shape[:2]


def crops_71667(manifest: dict, weights: dict[str, Path], out: Path, writer) -> dict:
    from ultralytics import YOLO

    models: dict[str, object] = {}
    matched = total = zero_match_images = n_crops = skipped_no_adult = 0
    by_source_split: dict[str, int] = {}
    for image, meta in sorted(manifest["images"].items()):
        key = model_key_for(meta.get("split"), str(meta.get("colony")))
        if key is None:
            continue
        # 유충 전용(n_adult == 0) 이미지는 성충 GT 가 없어 매칭 크롭이 나올 수 없다 → JSON(~2 MB)·예측 모두 생략.
        # n_adult 가 없는 옛 manifest 는 알 수 없으므로 기존대로 처리한다.
        if "n_adult" in meta and int(meta["n_adult"]) == 0:
            skipped_no_adult += 1
            continue
        lj = label_json_for(Path(image))
        if not lj.exists():
            continue
        boxes, _ = parse_annotations(json.loads(lj.read_text(encoding="utf-8")), "legacy3")
        gts = [(b[5], b[1:5]) for b in boxes]
        n_adult = sum(1 for c, _ in gts if c in ADULT_CATS)
        img = _imread(Path(image))
        if img is None:
            continue
        if key not in models:
            models[key] = YOLO(str(weights[key]))
        res = models[key].predict(source=img, verbose=False, **PRED_KW)[0]
        preds = [tuple(map(float, xy)) for xy in res.boxes.xyxy.cpu().numpy()]
        m = match_predictions(preds, gts)
        m_adult = sum(1 for _, c in m if c in ADULT_CATS)
        matched += m_adult
        total += n_adult
        zero_match_images += int(n_adult > 0 and m_adult == 0)
        for i, (box, cat) in enumerate(m):
            label = label_for(cat, bool(meta.get("has_varroa_adult")))
            if label is None:
                continue
            rel, (nh, nw) = _save(out, img, box, meta["split"], label, image, i)
            writer.writerow(row_71667(rel, label, meta, cat, image, nw, nh))
            count_crop(by_source_split, meta.get("source", "71667"), meta["split"], label)
            n_crops += 1
    return {"matched": matched, "total": total, "zero_match_images": zero_match_images, "crops_71667": n_crops,
            "skipped_no_adult": skipped_no_adult, "by_source_split": by_source_split}


def crops_external(rows: list[dict], root: Path, splits: dict[str, str], out: Path, writer,
                   counter: dict | None = None) -> dict:
    """외부 크롭 저장. 반환: {n, excluded_not_visible, unreadable, image_sizes(첫 3장 h×w — 8b 확인용)}."""
    n = excluded = unreadable = 0
    sizes: list[str] = []
    for r in rows:
        if not include_external(r):
            excluded += 1
            continue
        img = _imread(root / r["image"])
        if img is None:
            unreadable += 1
            continue
        if len(sizes) < 3:
            sizes.append(f"{img.shape[0]}x{img.shape[1]}")
        split = splits[str(r["image"])]
        key = f"{r['source']}/{Path(r['image']).as_posix()}"
        rel, (nh, nw) = _save(out, img, external_crop_box(r, img.shape), split, r["label"], key, 0)
        writer.writerow(row_external(rel, r, split, nw, nh))
        if counter is not None:
            count_crop(counter, r["source"], split, r["label"])
        n += 1
    return {"n": n, "excluded_not_visible": excluded, "unreadable": unreadable, "image_sizes": sizes}


def main() -> None:
    from training.data.external_sources import parse_ev2, parse_varroa_gt
    from training.data.make_split_manifest import split_external

    p = argparse.ArgumentParser()
    p.add_argument("--manifest", type=Path, default=Path("training/split_manifest.json"))
    p.add_argument("--weights-A", dest="weights_A", type=Path, required=True)
    p.add_argument("--weights-B", dest="weights_B", type=Path, required=True)
    p.add_argument("--weights-all", dest="weights_all", type=Path, required=True)
    p.add_argument("--out", type=Path, default=Path("training/crops"))
    p.add_argument("--external-varroa", type=Path, default=None, help="VarroaDataset 압축 해제 루트 (gt.csv 포함)")
    p.add_argument("--external-ev2", type=Path, default=None, help="EV2 dataset.zip 압축 해제 루트 (labels.txt 포함)")
    p.add_argument("--seed", type=int, default=42)
    a = p.parse_args()

    manifest = json.loads(a.manifest.read_text(encoding="utf-8"))
    weights = {"A": a.weights_A, "B": a.weights_B, "all": a.weights_all}
    a.out.mkdir(parents=True, exist_ok=True)
    with (a.out / "crops.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(CSV_COLUMNS)
        stats = crops_71667(manifest, weights, a.out, w)
        ext_rows: list[tuple[list[dict], Path]] = []
        if a.external_varroa:
            ext_rows.append((parse_varroa_gt(a.external_varroa / "gt.csv"), a.external_varroa))
        if a.external_ev2:
            ext_rows.append((parse_ev2(a.external_ev2 / "labels.txt"), a.external_ev2))
        splits = split_external([r for rows, _ in ext_rows for r in rows], a.seed) if ext_rows else {}
        for rows, root in ext_rows:
            src = rows[0]["source"] if rows else "external"
            res = crops_external(rows, root, splits, a.out, w, stats["by_source_split"])
            stats[f"crops_{src}"] = res.pop("n")
            stats[f"external_{src}"] = res
    sp = write_stats(a.out, stats.pop("matched"), stats.pop("total"), extra=stats)
    print(sp.read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
