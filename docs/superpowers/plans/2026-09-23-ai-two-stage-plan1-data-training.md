# 2-Stage 재설계 — 계획 1: 데이터·학습 파이프라인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 스펙 §9의 0~7단계 — Windows/4060 환경에서 71667(xyxy 정정)·VarroaDataset·EV2로 Stage-1 성충 검출기와 Stage-2 감염 분류기를 학습·보정·평가하고, `vdi.yaml`·`eval_history/v0.2.0-*.json`·`split_manifest.json`을 산출한다. 서빙·앱 동기는 계획 2.

**Architecture:** 원본 JSON을 xyxy로 파싱해 manifest(복사 없음)로 참조 → colony 단위 홀드아웃 `split_manifest.json` 하나를 모든 스크립트가 읽음 → Stage-1(YOLO11s, 2-fold) → out-of-fold 예측 박스로 224 크롭 사전 추출 → Stage-2(ShuffleNet-V2) 학습 → cal-A(Platt·τ)/cal-B(TPR·FPR) → `vdi.yaml` → 합성 의사-프레임 e2e 평가. VDI 수식은 `app/services/vdi.py`에 두어 평가와 서빙(계획 2)이 같은 코드를 쓴다.

**Tech Stack:** Python 3.11(Windows 네이티브), torch 2.4.1+cu121, ultralytics 8.3, torchvision, numpy/pandas/scikit-learn/scipy, onnx/onnxruntime, pytest. 실행 위치는 항상 `apps/ai/` (`pytest.ini: pythonpath=.`).

**Spec:** `docs/superpowers/specs/2026-09-22-ai-two-stage-redesign-design.md` (v2.1 ACCEPTED). 검증 기록: `docs/superpowers/specs/2026-09-23-ai-two-stage-redesign-adversarial-review.md`.

**실행 규칙(프로젝트):** 본체(Fable)가 계획·평가, 각 태스크 구현은 Opus 서브에이전트. 구현자는 이 문서의 자기 태스크와 스펙만 보고 작업하며, 완료 보고에 테스트 실행 출력을 첨부한다.

## Global Constraints

- Python 3.11+, Pydantic v2 only. 모든 파일 I/O에 `encoding="utf-8"` 명시. 학습 박스는 `PYTHONUTF8=1`.
- 71667 `bbox`는 **`[x1, y1, x2, y2]`**. `area` 필드와 교차검증한다.
- Stage-1은 **성충 1-class `bee`**(71667 category 4·5·6). 유충(0~3)은 검출 대상 아님.
- Stage-2 라벨: `성충_응애(5)=1`, `성충_정상(4)=0`, **`성충_날개불구(6)` 제외**, **감염 이미지 안의 정상 박스는 학습·cal·golden 음성에서 제외**.
- Stage-2 학습 크롭은 **out-of-fold Stage-1 예측 박스**(GT IoU ≥ 0.5 매칭)에서만 만든다. 크롭 여백 10%, 종횡비 유지 패딩 224.
- 불균형 처리는 **가중 샘플러만** (가중 CE·오버샘플 동시 사용 금지).
- τ는 cal-A에서 **FPR 1% 목표**로, TPR/FPR은 **cal-B**에서 측정. 둘은 colony-disjoint.
- golden·cal colony 목록은 Validation·Training 합집합 기준으로 한 번 동결하고, 이후 변경되면 테스트가 실패해야 한다. golden 이미지는 colony·device당 **10분 이내 연속 촬영을 디듀프**.
- 데이터 원본은 `D:\helpbee-data`(env `HELPBEE_DATA_ROOT`), 산출물(크롭·manifest·runs)은 `C:` 워크트리. 변환·split·golden은 **이미지를 복사하지 않는다** (manifest txt 참조).
- 학습 산출물(`*.pt`, `*.onnx`, `runs/`, 크롭 이미지)은 git 커밋 금지. `eval_history/*.json`·`vdi.yaml`·`split_manifest.json`은 커밋.
- 파일 삭제는 휴지통 이동만(`trash` / Windows `python tasks.py trash <path>`). 파괴적 git 명령 금지. 브랜치 `feature/*` → PR → develop.

## Review Focus

1. **`area` 필드가 없거나 0인 annotation** — 파서는 xyxy를 신뢰하되 교차검증 통계에서만 제외해야 하고, 예외로 죽으면 안 된다. → Task 3 `test_parse_skips_missing_area`.
2. **cal-A/cal-B/golden에 같은 colony가 들어가는 회귀** — manifest 생성 코드를 손대면 가장 먼저 깨진다. → Task 5 `test_manifest_colony_disjoint`.
3. **Stage-1 예측이 GT와 하나도 매칭되지 않는 이미지** — 크롭 0개로 조용히 빠지면 양성이 사라진다. 매칭률을 `stats.json`에 기록하고 50% 미만이면 경고. → Task 8 `test_match_rate_recorded`.
4. **TPR − FPR이 0.5 미만인 보정 계수** — Rogan–Gladen이 폭주한다. `vdi.yaml`에 `corrected:false`로 기록하고 raw를 그대로 써야 한다. → Task 10 `test_rogan_gladen_guard`.
5. **2.95 / 9.95 같은 반올림 경계** — 언어별 half-even 차이로 tier가 갈린다. AI가 `vdi_display`를 `ROUND_HALF_UP`으로 한 번만 만들고 tier는 그 값에서만 나온다. → Task 10 `test_display_rounding_boundaries`.

---

### Task 1: Windows 학습 환경 부트스트랩 + `tasks.py` 러너

**Files:**
- Create: `apps/ai/tasks.py`
- Create: `apps/ai/training/env/bootstrap.ps1`
- Modify: `apps/ai/requirements-gpu.txt` (torch 핀 명시, onnx/onnxruntime 추가)
- Test: `apps/ai/app/tests/unit/test_tasks_runner.py`

**Interfaces:**
- Produces: `python tasks.py <target>` — targets `doctor`, `trash <path>`; 이후 태스크가 `convert`, `split`, `golden`, `train-stage1`, `crops`, `train-stage2`, `gate0`, `eval`를 추가한다. 각 target은 `TARGETS: dict[str, Callable[[list[str]], int]]`에 등록.

- [ ] **Step 1: 러너 테스트 작성**

```python
# apps/ai/app/tests/unit/test_tasks_runner.py
import subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]  # apps/ai

def test_doctor_lists_required_tools():
    out = subprocess.run([sys.executable, "tasks.py", "doctor", "--dry"], cwd=ROOT,
                         capture_output=True, text=True, encoding="utf-8")
    assert out.returncode == 0
    for tool in ("python", "git", "7z", "torch", "ultralytics"):
        assert tool in out.stdout

def test_unknown_target_fails():
    out = subprocess.run([sys.executable, "tasks.py", "nope"], cwd=ROOT,
                         capture_output=True, text=True, encoding="utf-8")
    assert out.returncode == 2
```

- [ ] **Step 2: 실패 확인** — `cd apps/ai && pytest app/tests/unit/test_tasks_runner.py -q` → FAIL (`tasks.py` 없음)

- [ ] **Step 3: `tasks.py` 작성**

```python
# apps/ai/tasks.py
"""Windows/Mac 공용 태스크 러너 — Makefile 대체 (make 없는 네이티브 Windows용).
Usage: python tasks.py <target> [args...]   (apps/ai 에서 실행)
"""
from __future__ import annotations
import os, shutil, subprocess, sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parent
os.environ.setdefault("PYTHONUTF8", "1")
DATA_ROOT = Path(os.environ.get("HELPBEE_DATA_ROOT", r"D:\helpbee-data" if os.name == "nt" else str(ROOT / "training/datasets")))

def _run(cmd: list[str]) -> int:
    print("+", " ".join(cmd), flush=True)
    return subprocess.call(cmd, cwd=ROOT)

def doctor(args: list[str]) -> int:
    dry = "--dry" in args
    rows = []
    for tool in ("python", "git", "7z"):
        rows.append((tool, shutil.which(tool) or "MISSING"))
    for mod in ("torch", "ultralytics", "onnxruntime"):
        try:
            m = __import__(mod); rows.append((mod, getattr(m, "__version__", "ok")))
        except Exception as e:  # noqa: BLE001
            rows.append((mod, f"MISSING ({type(e).__name__})"))
    if not dry:
        try:
            import torch; rows.append(("cuda", f"{torch.cuda.is_available()} {torch.cuda.get_device_name(0) if torch.cuda.is_available() else ''}"))
        except Exception:
            rows.append(("cuda", "n/a"))
    rows.append(("HELPBEE_DATA_ROOT", str(DATA_ROOT)))
    for k, v in rows: print(f"{k:<20} {v}")
    return 0

def trash(args: list[str]) -> int:
    """휴지통 이동 (영구 삭제 금지 정책)."""
    if not args: print("usage: tasks.py trash <path>"); return 2
    p = Path(args[0]).resolve()
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        class SHFILEOPSTRUCTW(ctypes.Structure):
            _fields_ = [("hwnd", wintypes.HWND), ("wFunc", wintypes.UINT), ("pFrom", wintypes.LPCWSTR),
                        ("pTo", wintypes.LPCWSTR), ("fFlags", ctypes.c_uint16), ("fAnyOperationsAborted", wintypes.BOOL),
                        ("hNameMappings", ctypes.c_void_p), ("lpszProgressTitle", wintypes.LPCWSTR)]
        op = SHFILEOPSTRUCTW(None, 3, str(p) + "\0\0", None, 0x0040 | 0x0010 | 0x0004, False, None, None)  # FOF_ALLOWUNDO|NOCONFIRMATION|SILENT
        return int(ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op)))
    return _run(["trash", str(p)])

TARGETS: dict[str, Callable[[list[str]], int]] = {"doctor": doctor, "trash": trash}

def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in TARGETS:
        print("targets:", ", ".join(sorted(TARGETS))); return 2
    return TARGETS[sys.argv[1]](sys.argv[2:])

if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 부트스트랩 스크립트 작성** (학습 박스에서 1회, 관리자 PowerShell)

```powershell
# apps/ai/training/env/bootstrap.ps1
$ErrorActionPreference = "Stop"
winget install -e --id Python.Python.3.11 --accept-package-agreements --accept-source-agreements
winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
winget install -e --id 7zip.7zip --accept-package-agreements --accept-source-agreements
[Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
[Environment]::SetEnvironmentVariable("HELPBEE_DATA_ROOT", "D:\helpbee-data", "User")
New-Item -ItemType Directory -Force D:\helpbee-data | Out-Null
# 새 셸에서:
#   cd <repo>\apps\ai
#   py -3.11 -m venv .venv ; .\.venv\Scripts\Activate.ps1
#   pip install torch==2.4.1 torchvision==0.19.1 --index-url https://download.pytorch.org/whl/cu121
#   pip install -r requirements-gpu.txt
#   python tasks.py doctor      # cuda True NVIDIA GeForce RTX 4060 이어야 함
```

- [ ] **Step 5: `requirements-gpu.txt`에 핀 주석과 onnx 추가** — 파일 상단 주석에 `torch==2.4.1+cu121 / torchvision==0.19.1` (별도 index) 명시, 목록에 `onnx>=1.16`, `onnxruntime>=1.18`, `scipy>=1.11` 추가.

- [ ] **Step 6: 테스트 통과 확인** — `pytest app/tests/unit/test_tasks_runner.py -q` → PASS (Mac에서는 `7z MISSING`이 찍혀도 통과 — 존재 여부만 출력)

- [ ] **Step 7: 학습 박스에서 실행** — `ssh beetrain`, `bootstrap.ps1` 실행 후 새 셸에서 venv·torch 설치, `python tasks.py doctor` 출력에 `cuda True ... RTX 4060` 확인. 결과를 `docs/05-implementation/2026-09-XX-training-box-bootstrap.md`에 붙여넣는다.

- [ ] **Step 8: 커밋** — `git add apps/ai/tasks.py apps/ai/training/env/bootstrap.ps1 apps/ai/requirements-gpu.txt apps/ai/app/tests/unit/test_tasks_runner.py && git commit -m "chore(ai): Windows 학습 환경 부트스트랩 + tasks.py 러너"`

---

### Task 2: UTF-8 인코딩 가드

**Files:**
- Modify: `apps/ai/training/train.py:69`, `apps/ai/training/eval.py:49,103`, `apps/ai/training/data/golden_holdout.py:38,203`, `apps/ai/training/data/split_strategy.py:258`
- Test: `apps/ai/app/tests/unit/test_encoding_guard.py`

- [ ] **Step 1: 정적 가드 테스트 작성**

```python
# apps/ai/app/tests/unit/test_encoding_guard.py
import re
from pathlib import Path

TRAINING = Path(__file__).resolve().parents[3] / "training"
BIN = ("'rb'", '"rb"', "'wb'", '"wb"')

def test_no_bare_text_io_in_training():
    offenders = []
    for py in TRAINING.rglob("*.py"):
        for i, line in enumerate(py.read_text(encoding="utf-8").splitlines(), 1):
            bare_read = ".read_text()" in line
            bare_write = ".write_text(" in line and "encoding=" not in line
            bare_open = re.search(r"\bopen\(", line) and "encoding=" not in line and not any(b in line for b in BIN)
            if bare_read or bare_write or bare_open:
                offenders.append(f"{py.relative_to(TRAINING)}:{i}: {line.strip()}")
    assert not offenders, "\n".join(offenders)
```

- [ ] **Step 2: 실패 확인** — `pytest app/tests/unit/test_encoding_guard.py -q` → FAIL, 6곳 나열

- [ ] **Step 3: 각 위치를 `encoding="utf-8"`로 수정** (예: `cfg = yaml.safe_load(args.config.read_text(encoding="utf-8"))`). `open(...)` 호출은 바이너리가 아니면 전부 `encoding="utf-8"` 추가.

- [ ] **Step 4: 통과 확인** — `pytest app/tests/unit/test_encoding_guard.py -q` → PASS. 전체 `pytest -q`도 PASS.

- [ ] **Step 5: 커밋** — `git commit -am "fix(ai): training 스크립트 텍스트 I/O에 utf-8 명시 (Windows cp949 크래시 방지)"`

---

### Task 3: 71667 파서 — xyxy 정정 · area 교차검증 · 성충 1-class · manifest 모드

**Files:**
- Modify: `apps/ai/training/data/aihub_to_yolo.py` (docstring, `CLASS_MAPPING`, `_parse_one_json`, `write_yolo`, `main`)
- Modify: `apps/ai/training/configs/dataset.yaml` (`nc: 1`, `names: [bee]`)
- Modify: `apps/ai/training/datasets/AIHUB_71667.md` §4·§6·§7 (xyxy 정정, 성충/유충 통계 표로 교체)
- Test: `apps/ai/app/tests/unit/test_aihub_to_yolo.py`

**Interfaces:**
- Produces: `parse_annotations(d: dict, mapping: str) -> tuple[list[Box], dict]` — `Box = (cls:int, x1,y1,x2,y2 float 픽셀, cat71667:int, area_ok:bool)`; `CLASS_MAPPINGS = {"adult1": {4:0,5:0,6:0}, "legacy3": {...}}`; `yolo_line(cls,x1,y1,x2,y2,W,H) -> str`; `write_manifest(samples, output, split) -> Path` (txt, 한 줄 = 절대 이미지 경로; 라벨 txt는 `labels/<split>/`에만 작성).

- [ ] **Step 1: 테스트 작성 (합성 JSON, 데이터셋 불필요)**

```python
# apps/ai/app/tests/unit/test_aihub_to_yolo.py
import json, os
from pathlib import Path
import pytest
from training.data.aihub_to_yolo import parse_annotations, CLASS_MAPPINGS, yolo_line

def _doc(anns):
    return {"image": {"width": 1920, "height": 1080, "filename": "a.jpg"}, "annotations": anns,
            "collection": {"device": "소비판촬영기", "datetime": "20230820_105708_001"}, "colony": {"id": "007"}}

def test_bbox_is_xyxy_and_area_crosschecks():
    d = _doc([{"category_id": 5, "bbox": [224.77, 413.65, 814.69, 1078.2], "area": 392031}])
    boxes, stats = parse_annotations(d, "adult1")
    (cls, x1, y1, x2, y2, cat, area_ok), = boxes
    assert (cls, cat) == (0, 5)
    assert (round(x2 - x1), round(y2 - y1)) == (590, 665)          # xyxy: w=589.92, h=664.55
    assert area_ok and stats["area_match"] == 1

def test_adult1_mapping_drops_larvae_keeps_all_adults():
    d = _doc([{"category_id": c, "bbox": [0, 0, 10, 10], "area": 100} for c in range(7)])
    boxes, _ = parse_annotations(d, "adult1")
    assert sorted(b[5] for b in boxes) == [4, 5, 6] and all(b[0] == 0 for b in boxes)

def test_parse_skips_missing_area():
    d = _doc([{"category_id": 4, "bbox": [10, 10, 50, 50]}, {"category_id": 4, "bbox": [10, 10, 50, 50], "area": 0}])
    boxes, stats = parse_annotations(d, "adult1")
    assert len(boxes) == 2 and stats["area_missing"] == 2 and stats["area_match"] == 0

def test_yolo_line_normalized():
    line = yolo_line(0, 0, 0, 960, 540, 1920, 1080)
    assert line == "0 0.250000 0.250000 0.500000 0.500000"

SAMPLE = Path(os.environ.get("AIHUB_SAMPLE_DIR", ""))
@pytest.mark.skipif(not SAMPLE.exists(), reason="AIHUB_SAMPLE_DIR 없음")
def test_sample_area_crosscheck_ratio():
    match = missing = total = 0
    for jp in SAMPLE.rglob("*.json"):
        d = json.loads(jp.read_text(encoding="utf-8"))
        _, s = parse_annotations(d, "legacy3")
        match += s["area_match"]; missing += s["area_missing"]; total += s["n_boxes"]
    assert match / max(1, total - missing) > 0.99   # 4208/4210 재현
```

- [ ] **Step 2: 실패 확인** — `pytest app/tests/unit/test_aihub_to_yolo.py -q` → FAIL (`parse_annotations` 없음)

- [ ] **Step 3: 파서 구현** — `aihub_to_yolo.py`에 추가/교체:

```python
CLASS_MAPPINGS: dict[str, dict[int, int | None]] = {
    # v0.2.0 Stage-1: 성충만, 1-class `bee`
    "adult1": {0: None, 1: None, 2: None, 3: None, 4: 0, 5: 0, 6: 0},
    # v0.1.0 호환(참고용)
    "legacy3": {0: 0, 1: 1, 2: 2, 3: 2, 4: 0, 5: 1, 6: 2},
}
Box = tuple[int, float, float, float, float, int, bool]

def parse_annotations(d: dict, mapping: str) -> tuple[list[Box], dict]:
    """71667 JSON → (boxes, stats). bbox는 [x1,y1,x2,y2] 픽셀. area 필드로 교차검증."""
    m = CLASS_MAPPINGS[mapping]
    img = d.get("image", {}); W, H = float(img.get("width", 1920)), float(img.get("height", 1080))
    boxes: list[Box] = []; stats = {"n_boxes": 0, "area_match": 0, "area_missing": 0, "area_mismatch": 0}
    for ann in d.get("annotations", []):
        cat = ann.get("category_id"); bb = ann.get("bbox")
        if cat not in m or m[cat] is None or not bb or len(bb) != 4: continue
        x1, y1, x2, y2 = (float(v) for v in bb)
        x1, y1 = max(0.0, x1), max(0.0, y1); x2, y2 = min(W, x2), min(H, y2)
        if x2 - x1 <= 0 or y2 - y1 <= 0: continue
        stats["n_boxes"] += 1
        area = ann.get("area")
        if not area:  # None 또는 0
            stats["area_missing"] += 1; area_ok = False
        else:
            area_ok = abs((x2 - x1) * (y2 - y1) - float(area)) / float(area) < 0.02
            stats["area_match" if area_ok else "area_mismatch"] += 1
        boxes.append((m[cat], x1, y1, x2, y2, int(cat), area_ok))
    return boxes, stats

def yolo_line(cls: int, x1: float, y1: float, x2: float, y2: float, W: float, H: float) -> str:
    cw, ch = x2 - x1, y2 - y1
    return f"{cls} {(x1 + cw/2)/W:.6f} {(y1 + ch/2)/H:.6f} {cw/W:.6f} {ch/H:.6f}"
```

`_parse_one_json`은 위 함수를 호출하도록 바꾸고, `Sample.meta`에 `"cats": [b[5] for b in boxes]`, `"has_varroa_adult": any(b[5]==5 ...)`, `"area_stats": stats`를 추가. `main`에 `--mapping {adult1,legacy3}`(기본 adult1)와 `--manifest`(이미지 복사·심링크 없이 `images_<split>.txt` 작성) 추가. `write_manifest`:

```python
def write_manifest(samples: list[Sample], output: Path, split_name: str) -> Path:
    lbl_dir = output / "labels" / split_name; lbl_dir.mkdir(parents=True, exist_ok=True)
    lines = []
    for s in samples:
        (lbl_dir / Path(s.out_filename).with_suffix(".txt").name).write_text("\n".join(s.yolo_lines) + "\n", encoding="utf-8")
        lines.append(str(s.image_path.resolve()))
    mf = output / f"images_{split_name}.txt"; mf.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return mf
```
Ultralytics는 이미지 목록 txt를 받지만 라벨 경로를 이미지 경로의 `images`→`labels` 치환으로 찾는다. 원본 경로에 `images` 세그먼트가 없으므로 Task 7의 `yolo_list_dataset.py`가 `img2label_paths`를 `output/labels/<split>/<stem>.txt`로 패치한다.

- [ ] **Step 4: 통과 확인** — `AIHUB_SAMPLE_DIR=/Users/hyeonsyu/Documents/02_Work/04_MRMR/01_HelpBee/apps/ai/training/datasets/Sample pytest app/tests/unit/test_aihub_to_yolo.py -q` → 5 PASS

- [ ] **Step 5: `dataset.yaml` → `nc: 1`, `names: [bee]`; `AIHUB_71667.md` §4 bbox 주석을 `[x1,y1,x2,y2]`로, §6·§7을 xyxy 재계산 표(성충_정상 263×269 / 성충_응애 400×354 / 유충_정상 116×117 / 유충_응애 489×500, 감염 벌 56/56 `state=정상`)로 교체하고 상단 🔴 정정 블록을 "정정 완료(2026-09)"로 갱신.

- [ ] **Step 6: 커밋** — `git commit -am "fix(ai): 71667 bbox xyxy 정정 + area 교차검증 + 성충 1-class 매핑 + manifest 모드"`

---

### Task 4: 외부 데이터 정규화 (VarroaDataset · EV2) + 다운로드 절차

**Files:**
- Create: `apps/ai/training/data/external_sources.py`
- Create: `apps/ai/training/data/DOWNLOAD.md`
- Test: `apps/ai/app/tests/unit/test_external_sources.py`

**Interfaces:**
- Produces: `parse_varroa_gt(csv_path) -> list[dict]`, `parse_ev2(jsonl_path) -> list[dict]`; 행 = `{source:str, image:Path, label:int, split:str, boxes:list[tuple], varroa_visible: bool|None}`. VarroaDataset 라벨 `1`·`3` → 1, `0` → 0, split은 경로 첫 세그먼트(train/test/val).

- [ ] **Step 1: 테스트 작성**

```python
# apps/ai/app/tests/unit/test_external_sources.py
from pathlib import Path
from training.data.external_sources import parse_varroa_gt, parse_ev2

def test_varroa_gt_labels_1_and_3_positive(tmp_path: Path):
    p = tmp_path / "gt.csv"
    p.write_text("test/v/a.png 1 84 143 109 172 54 142 82 172\ntest/v/b.png 0\ntrain/v/c.png 3 92 115 133 149\n", encoding="utf-8")
    rows = parse_varroa_gt(p)
    assert [(r["label"], r["split"], len(r["boxes"])) for r in rows] == [(1, "test", 2), (0, "test", 0), (1, "train", 1)]

def test_ev2_visible_flag_kept(tmp_path: Path):
    p = tmp_path / "labels.jsonl"
    p.write_text('{"frame":"x/1.png","bees":[{"bbox":[1,2,50,60],"infested":true,"varroa_visible":false}]}\n', encoding="utf-8")
    rows = parse_ev2(p)
    assert rows[0]["label"] == 1 and rows[0]["varroa_visible"] is False and rows[0]["boxes"] == [(1, 2, 50, 60)]
```

- [ ] **Step 2: 실패 확인** — `pytest app/tests/unit/test_external_sources.py -q` → FAIL

- [ ] **Step 3: 구현**

```python
# apps/ai/training/data/external_sources.py
"""외부 감염 라벨 데이터 정규화. VarroaDataset(Zenodo 4085044, CC BY 4.0), EV2(Zenodo 13771384, CC BY 4.0)."""
from __future__ import annotations
import json
from pathlib import Path

VARROA_ZENODO = "https://zenodo.org/records/4085044"
EV2_ZENODO = "https://zenodo.org/records/13771384"   # dataset.zip MD5 c626a1f198cf7d0f41eae9c2660b0985

def parse_varroa_gt(csv_path: Path) -> list[dict]:
    rows = []
    for line in csv_path.read_text(encoding="utf-8").splitlines():
        t = line.split()
        if len(t) < 2: continue
        coords = list(map(int, t[2:])); boxes = [tuple(coords[i:i+4]) for i in range(0, len(coords) - len(coords) % 4, 4)]
        rows.append({"source": "varroadataset", "image": Path(t[0]), "label": 1 if t[1] in ("1", "3") else 0,
                     "split": t[0].split("/")[0], "boxes": boxes, "varroa_visible": None})
    return rows

def parse_ev2(jsonl_path: Path) -> list[dict]:
    rows = []
    for line in jsonl_path.read_text(encoding="utf-8").splitlines():
        if not line.strip(): continue
        d = json.loads(line)
        for b in d.get("bees", []):
            rows.append({"source": "ev2", "image": Path(d["frame"]), "label": int(bool(b.get("infested"))),
                         "split": "unsplit", "boxes": [tuple(b["bbox"])], "varroa_visible": b.get("varroa_visible")})
    return rows
```
EV2의 실제 JSONL 필드명은 zip 해제 후 확인해 이 파서를 맞춘다(테스트 fixture도 함께 갱신). EV2 hold-out 15%는 Task 5의 manifest에서 프레임 단위로 잘라 `split`에 기록.

- [ ] **Step 4: 통과 확인** — PASS

- [ ] **Step 5: `DOWNLOAD.md` 작성** — 학습 박스 절차: (1) Git Bash에서 `curl -fsSL -o ~/aihubshell https://api.aihub.or.kr/info/aihubshell.sh`; (2) `bash ~/aihubshell -mode l -datasetkey 71667`로 파일키·용량 확인(71488도 동일하게 실행해 스펙 §5.3 표 갱신); (3) Validation 셋 `-filekey 521779,521780` → `D:\helpbee-data\aihub-71667-val`; (4) Training 셋은 백그라운드로 `D:\helpbee-data\aihub-71667-train`; (5) 7-Zip: `7z x -mcp=65001 <zip> -oD:\helpbee-data\...` 후 `01.원천데이터` 폴더명 assert; (6) VarroaDataset·EV2 zip은 Zenodo에서 받아 `D:\helpbee-data\external\{varroadataset,ev2}`, EV2는 MD5 확인. **API 키는 절대 커밋·로그 금지.**

- [ ] **Step 6: 커밋** — `git add apps/ai/training/data/external_sources.py apps/ai/training/data/DOWNLOAD.md apps/ai/app/tests/unit/test_external_sources.py && git commit -m "feat(ai): VarroaDataset/EV2 정규화 파서 + 데이터 다운로드 절차"`

---

### Task 5: `split_manifest.json` — colony 홀드아웃(golden·cal-A·cal-B) + 디듀프 + 동결 테스트

**Files:**
- Create: `apps/ai/training/data/make_split_manifest.py`
- Create(커밋): `apps/ai/training/split_manifest.json`, `apps/ai/training/data/frozen_colonies.json`
- Test: `apps/ai/app/tests/unit/test_split_manifest.py`

**Interfaces:**
- Produces: `build_manifest(items: list[dict], seed:int, golden_frac=0.10, cal_frac=0.15, dedupe_min=10, frozen: dict|None=None) -> dict`; item = `{"image": str, "colony": str, "device": str, "ts": datetime, "has_varroa_adult": bool, "n_adult": int, "source": "71667-val"|"71667-train"}`. 출력 스키마:
```json
{"seed": 42, "frozen_colonies": {"golden": [...], "cal_a": [...], "cal_b": [...]},
 "images": {"<abs path>": {"split": "train|val|golden|cal_a|cal_b|dropped_dup", "colony": "007", "device": "...", "ts": "...", "source": "...", "has_varroa_adult": true, "n_adult": 4}}}
```

- [ ] **Step 1: 테스트 작성**

```python
# apps/ai/app/tests/unit/test_split_manifest.py
from datetime import datetime, timedelta
from training.data.make_split_manifest import build_manifest

def _items(n_col=12, per=40):
    out = []
    for c in range(n_col):
        t0 = datetime(2023, 8, 20, 9, 0, 0)
        for i in range(per):
            out.append({"image": f"/d/{c:03d}/{i}.jpg", "colony": f"{c:03d}", "device": "소비판촬영기" if c % 2 else "플레이트촬영기",
                        "ts": t0 + timedelta(seconds=4 * i if i % 5 else 900 * i), "has_varroa_adult": i % 7 == 0, "n_adult": 4, "source": "71667-val"})
    return out

def test_manifest_colony_disjoint():
    m = build_manifest(_items(), seed=42)
    g, a, b = (set(m["frozen_colonies"][k]) for k in ("golden", "cal_a", "cal_b"))
    assert not (g & a) and not (g & b) and not (a & b)
    trainval = {v["colony"] for v in m["images"].values() if v["split"] in ("train", "val")}
    assert not (trainval & (g | a | b))

def test_golden_dedupes_10min_bursts():
    m = build_manifest(_items(), seed=42)
    kept = [v for v in m["images"].values() if v["split"] == "golden"]
    by = {}
    for v in kept: by.setdefault((v["colony"], v["device"]), []).append(datetime.fromisoformat(v["ts"]))
    for ts in by.values():
        ts.sort(); assert all((ts[i+1] - ts[i]).total_seconds() >= 600 for i in range(len(ts) - 1))

def test_frozen_colonies_stable_when_superset_added():
    base = build_manifest(_items(), seed=42)["frozen_colonies"]
    more = _items() + [dict(i, image=i["image"].replace("/d/", "/e/"), source="71667-train") for i in _items(n_col=12, per=5)]
    again = build_manifest(more, seed=42, frozen=base)["frozen_colonies"]
    assert again == base
```

- [ ] **Step 2: 실패 확인** — FAIL

- [ ] **Step 3: 구현**

```python
# apps/ai/training/data/make_split_manifest.py
"""단일 split 진실 소스. golden/cal-A/cal-B는 colony 홀드아웃, train/val은 colony 내 시간 블록."""
from __future__ import annotations
import argparse, json, random
from collections import defaultdict
from datetime import datetime
from pathlib import Path

def build_manifest(items: list[dict], seed: int, golden_frac=0.10, cal_frac=0.15, dedupe_min=10, frozen: dict | None = None) -> dict:
    rng = random.Random(seed)
    colonies = sorted({i["colony"] for i in items})
    if frozen:
        g, a, b = (list(frozen[k]) for k in ("golden", "cal_a", "cal_b"))
    else:
        with_v = sorted({i["colony"] for i in items if i["has_varroa_adult"]}); rng.shuffle(with_v)
        rest = [c for c in colonies if c not in with_v]; rng.shuffle(rest)
        n_g = max(3, round(len(colonies) * golden_frac)); n_c = max(2, round(len(colonies) * cal_frac))
        g = (with_v[:3] + rest)[:n_g]; pool = [c for c in colonies if c not in g]; rng.shuffle(pool)
        half = max(1, n_c // 2); a, b = pool[:half], pool[half:half * 2]
    held = {c: "golden" for c in g} | {c: "cal_a" for c in a} | {c: "cal_b" for c in b}
    out = {"seed": seed, "frozen_colonies": {"golden": g, "cal_a": a, "cal_b": b}, "images": {}}
    by_col = defaultdict(list)
    for it in items: by_col[it["colony"]].append(it)
    def rec(it, split):
        out["images"][it["image"]] = {"split": split, "colony": it["colony"], "device": it["device"], "ts": it["ts"].isoformat(),
                                      "source": it["source"], "has_varroa_adult": bool(it["has_varroa_adult"]), "n_adult": int(it["n_adult"])}
    for col, its in by_col.items():
        its.sort(key=lambda x: x["ts"])
        if col in held:
            split = held[col]; last = {}
            for it in its:
                key = (col, it["device"]); prev = last.get(key); s = split
                if split == "golden" and prev is not None and (it["ts"] - prev).total_seconds() < dedupe_min * 60:
                    s = "dropped_dup"
                else:
                    last[key] = it["ts"]
                rec(it, s)
        else:
            cut = int(len(its) * 0.8)
            for k, it in enumerate(its): rec(it, "train" if k < cut else "val")
    return out

def load_items_from_aihub(roots: list[Path], source_tags: list[str]) -> list[dict]:
    from training.data.aihub_to_yolo import parse_annotations, _resolve_image_path
    items = []
    for root, tag in zip(roots, source_tags):
        for jp in (root / "02.라벨링데이터").rglob("*.json"):
            d = json.loads(jp.read_text(encoding="utf-8"))
            img = _resolve_image_path(jp, d["image"]["filename"])
            if img is None: continue
            boxes, _ = parse_annotations(d, "adult1")
            ts = d.get("collection", {}).get("datetime", "")[:15]
            try: t = datetime.strptime(ts, "%Y%m%d_%H%M%S")
            except ValueError: continue
            items.append({"image": str(img.resolve()), "colony": str(d.get("colony", {}).get("id")), "device": d.get("collection", {}).get("device", ""),
                          "ts": t, "has_varroa_adult": any(b[5] == 5 for b in boxes), "n_adult": len(boxes), "source": tag})
    return items

def main():
    p = argparse.ArgumentParser(); p.add_argument("--roots", nargs="+", type=Path, required=True); p.add_argument("--tags", nargs="+", required=True)
    p.add_argument("--output", type=Path, default=Path("training/split_manifest.json")); p.add_argument("--seed", type=int, default=42)
    p.add_argument("--frozen", type=Path, default=None, help="기존 manifest — frozen_colonies 유지")
    a = p.parse_args()
    frozen = json.loads(a.frozen.read_text(encoding="utf-8"))["frozen_colonies"] if a.frozen else None
    m = build_manifest(load_items_from_aihub(a.roots, a.tags), a.seed, frozen=frozen)
    a.output.write_text(json.dumps(m, ensure_ascii=False, indent=1), encoding="utf-8")
    Path("training/data/frozen_colonies.json").write_text(json.dumps(m["frozen_colonies"], ensure_ascii=False, indent=1), encoding="utf-8")
    from collections import Counter; print(Counter(v["split"] for v in m["images"].values()))

if __name__ == "__main__": main()
```

- [ ] **Step 4: 통과 확인** — PASS. `tasks.py`에 `split` target 등록(`python -m training.data.make_split_manifest --roots <DATA_ROOT>/aihub-71667-val --tags 71667-val`).

- [ ] **Step 5: 학습 박스에서 Validation 셋으로 manifest 생성** → `training/split_manifest.json`·`training/data/frozen_colonies.json` 커밋. Training 셋 도착 후 `--frozen training/split_manifest.json`으로 재생성(동결 유지) → 재커밋.

- [ ] **Step 6: 동결 회귀 테스트 추가** — `test_committed_manifest_frozen_colonies_unchanged`: 커밋된 manifest의 `frozen_colonies`가 `training/data/frozen_colonies.json`과 같은지 확인(둘 중 하나 없으면 skip).

- [ ] **Step 7: 커밋** — `git commit -m "feat(ai): split_manifest — golden/cal-A/cal-B colony 홀드아웃 + 10분 디듀프 + 동결"`

---

### Task 6: golden 셀렉터 재작성 (JSON category 기반)

**Files:**
- Modify: `apps/ai/training/data/golden_holdout.py` (`has_varroa_label` 제거, manifest 기반으로 교체)
- Test: `apps/ai/app/tests/unit/test_golden_holdout.py`

**Interfaces:**
- Produces: `select_golden(manifest: dict, n_varroa=100, n_normal=200, seed=42) -> dict[str, list[str]]` → `{"varroa": [...paths], "normal": [...]}`. 조건: 모두 `split=="golden"`, `varroa` = `has_varroa_adult`, `normal` = `n_adult ≥ 1` & 응애 없음, colony ≥3, device ≥2(부족하면 `ValueError`).

- [ ] **Step 1: 테스트**

```python
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
```

- [ ] **Step 2: 실패 확인 → Step 3: 구현**

```python
def select_golden(manifest: dict, n_varroa=100, n_normal=200, seed=42, min_colonies=3, min_devices=2) -> dict[str, list[str]]:
    import random
    rng = random.Random(seed)
    pool = [(p, v) for p, v in manifest["images"].items() if v["split"] == "golden"]
    var = [p for p, v in pool if v["has_varroa_adult"]]; nor = [p for p, v in pool if not v["has_varroa_adult"] and v["n_adult"] > 0]
    rng.shuffle(var); rng.shuffle(nor)
    sel = {"varroa": var[:n_varroa], "normal": nor[:n_normal]}
    chosen = [manifest["images"][p] for p in sel["varroa"] + sel["normal"]]
    if len({v["colony"] for v in chosen}) < min_colonies or len({v["device"] for v in chosen}) < min_devices:
        raise ValueError("golden 다양성 부족: colony/device 수 확인")
    return sel
```
`main`은 `--manifest training/split_manifest.json --output training/golden.json`로 선택 결과(경로 목록)만 기록(이미지 복사 없음). 기존 `has_varroa_label`·`extract_golden`·`write_golden` 삭제.

- [ ] **Step 4: PASS → Step 5: `tasks.py golden` target → Step 6: 커밋** `feat(ai): golden 셀렉터를 JSON category·manifest 기반으로 재작성`

---

### Task 7: Stage-1 학습 — 전체 오버라이드 · resolved config · 2-fold · manifest 데이터셋

**Files:**
- Create: `apps/ai/training/configs/stage1.yaml`
- Create: `apps/ai/training/data/yolo_list_dataset.py`
- Create: `apps/ai/training/make_fold_lists.py`
- Modify: `apps/ai/training/train.py`
- Test: `apps/ai/app/tests/unit/test_train_overrides.py`

**Interfaces:**
- Produces: `train.py --config stage1.yaml --set key=value ... --fold {A,B,all}`; run 종료 시 `runs/yolo/<name>/resolved_config.json`. `apply_overrides(cfg: dict, sets: list[str]) -> dict`, `dump_resolved(cfg: dict, save_dir: Path) -> Path`. `make_fold_lists.py`가 manifest의 train/val을 colony 기준 A/B 두 fold로 나눠 `training/lists/stage1_{A,B,all}_{train,val}.txt` + `stage1_{A,B,all}.yaml` 생성.

- [ ] **Step 1: 테스트**

```python
# apps/ai/app/tests/unit/test_train_overrides.py
from training.train import apply_overrides, dump_resolved
def test_set_overrides_parse_types():
    cfg = {"epochs": 100, "lr0": 0.001, "amp": True, "name": "x"}
    out = apply_overrides(cfg, ["epochs=5", "lr0=3e-4", "amp=false", "name=v0.2.0-s1A", "scale=0.15"])
    assert out == {"epochs": 5, "lr0": 3e-4, "amp": False, "name": "v0.2.0-s1A", "scale": 0.15}
def test_dump_resolved_writes_json(tmp_path):
    p = dump_resolved({"a": 1}, tmp_path); assert p.name == "resolved_config.json" and '"a": 1' in p.read_text(encoding="utf-8")
```

- [ ] **Step 2: 실패 확인 → Step 3: 구현** — `train.py`에:

```python
import json
def _coerce(v: str):
    if v.lower() in ("true", "false"): return v.lower() == "true"
    try: return int(v)
    except ValueError:
        try: return float(v)
        except ValueError: return v
def apply_overrides(cfg: dict, sets: list[str]) -> dict:
    out = dict(cfg)
    for s in sets: k, _, v = s.partition("="); out[k] = _coerce(v)
    return out
def dump_resolved(cfg: dict, save_dir: Path) -> Path:
    p = Path(save_dir) / "resolved_config.json"; p.write_text(json.dumps(cfg, ensure_ascii=False, indent=2, default=str), encoding="utf-8"); return p
```
`--set`(nargs="*")·`--fold` 인자 추가; `--fold A`면 `cfg["data"]`를 `training/lists/stage1_A.yaml`로 교체; 학습 후 `dump_resolved(cfg, save_dir)`. `yolo_list_dataset.py`:

```python
"""manifest(txt 이미지 목록) 모드에서 라벨을 output/labels/<split>/<stem>.txt 에서 찾도록 ultralytics 패치."""
from pathlib import Path
def patch_label_lookup(label_root: Path) -> None:
    from ultralytics.data import utils
    def img2label_paths(img_paths):
        return [str(label_root / (Path(p).stem + ".txt")) for p in img_paths]
    utils.img2label_paths = img2label_paths
```
`train.py`는 `cfg.get("label_root")`가 있으면 ultralytics import 직후 `patch_label_lookup(Path(label_root))`를 호출한다(split별 라벨 디렉터리는 `lists/stage1_X.yaml`의 `label_root: ...` 키로 지정 — train/val 라벨을 한 폴더 `output/labels/all/`에 두면 단일 root로 충분).

`stage1.yaml` (스펙 §6):
```yaml
data: training/lists/stage1_all.yaml
model: yolo11s.yaml
pretrained: yolo11s.pt
epochs: 100
patience: 20
batch: -1
imgsz: 1024
device: 0
workers: 4
optimizer: AdamW
lr0: 0.001
lrf: 0.01
cos_lr: true
box: 7.5
cls: 0.5
dfl: 1.5
hsv_h: 0.01
hsv_s: 0.4
hsv_v: 0.3
degrees: 15.0
translate: 0.1
scale: 0.85        # ultralytics scale=gain → 배율 [0.15, 1.85]
mosaic: 1.0
mixup: 0.0
copy_paste: 0.0    # bbox 라벨에서 no-op (2026-06-08 확인)
close_mosaic: 10
max_det: 1500
project: training/runs/yolo
name: v0.2.0-stage1
seed: 42
deterministic: true
amp: true
```

- [ ] **Step 4: PASS 확인 → Step 5: `make_fold_lists.py`** — manifest에서 `train`·`val` 이미지를 colony 이름 해시(`hash(colony) % 2`)로 A/B 분할, `stage1_{A,B,all}.yaml`(`train: lists/stage1_X_train.txt`, `val: lists/stage1_X_val.txt`, `nc: 1`, `names: [bee]`, `label_root: <output>/labels/all`) 생성. 라벨은 Task 3의 `--manifest` 모드로 `output/labels/all/`에 한 번 생성.

- [ ] **Step 6: 학습 박스 실행** — `python tasks.py train-stage1 --fold A` / `--fold B` / `--fold all` (Validation 5k로 파이프라인 검증 → Training 셋 2.5만 + 71488 서브셋). 첫 epoch 시간을 `docs/05-implementation/`에 기록해 스펙 §6 추정치 갱신. 71488은 다운로드 후 JSON 필드를 확인하고 `aihub_to_yolo.py`에 `--schema 71488` 분기(성충 클래스만 `bee`)를 추가한다 — 필드명 확인 전에는 구현하지 않는다.

- [ ] **Step 7: 커밋** — `feat(ai): stage1 config + train.py 전체 오버라이드·resolved config·2-fold 리스트`

---

### Task 8: out-of-fold 크롭 추출 `make_crops.py`

**Files:**
- Create: `apps/ai/training/data/make_crops.py`
- Test: `apps/ai/app/tests/unit/test_make_crops.py`

**Interfaces:**
- Produces: `iou(a,b)`, `match_predictions(preds: list[box], gts: list[(cat,box)], iou_thr=0.5) -> list[(pred_box, cat)]`, `label_for(cat:int, image_has_varroa:bool) -> int|None`, `crop_pad_224(img: np.ndarray, box, margin=0.10, size=224) -> (np.ndarray(224,224,3), np.ndarray native)`, `write_stats(out_dir, matched, total) -> Path`. CLI가 `crops/{split}/{label}/*.png` + `crops/crops.csv`(`path,label,source,colony,device,split,native_w,native_h,cat71667,image`) + `crops/stats.json`.

- [ ] **Step 1: 테스트**

```python
# apps/ai/app/tests/unit/test_make_crops.py
import json
import numpy as np
from training.data.make_crops import match_predictions, crop_pad_224, label_for, write_stats
def test_iou_match_and_label_rules():
    preds = [(0, 0, 100, 100), (500, 500, 600, 600)]
    gts = [(5, (5, 5, 95, 95)), (6, (500, 500, 600, 600)), (4, (900, 900, 950, 950))]
    m = match_predictions(preds, gts)
    assert m == [((0, 0, 100, 100), 5), ((500, 500, 600, 600), 6)]
    assert label_for(5, image_has_varroa=True) == 1
    assert label_for(4, image_has_varroa=False) == 0
    assert label_for(4, image_has_varroa=True) is None      # 감염 이미지 내 정상 → 제외
    assert label_for(6, image_has_varroa=False) is None     # DWV 제외
def test_crop_pad_keeps_aspect():
    img = np.zeros((1080, 1920, 3), np.uint8)
    out, native = crop_pad_224(img, (100, 100, 300, 200))
    assert out.shape == (224, 224, 3) and native.shape[0] < native.shape[1]
def test_match_rate_recorded(tmp_path):
    p = write_stats(tmp_path, matched=40, total=100)
    s = json.loads(p.read_text(encoding="utf-8")); assert s["match_rate"] == 0.4 and s["warning"]
```

- [ ] **Step 2: 실패 확인 → Step 3: 구현**

```python
# apps/ai/training/data/make_crops.py
from __future__ import annotations
import json
from pathlib import Path
import numpy as np

def iou(a, b):
    x1, y1, x2, y2 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    inter = max(0, x2 - x1) * max(0, y2 - y1); ua = (a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - inter
    return inter / ua if ua else 0.0

def match_predictions(preds, gts, iou_thr=0.5):
    used, out = set(), []
    for p in preds:
        best, bi = 0.0, -1
        for k, (cat, g) in enumerate(gts):
            if k in used: continue
            v = iou(p, g)
            if v > best: best, bi = v, k
        if best >= iou_thr: used.add(bi); out.append((p, gts[bi][0]))
    return out

def label_for(cat: int, image_has_varroa: bool):
    if cat == 5: return 1
    if cat == 4: return None if image_has_varroa else 0
    return None  # 6 DWV 및 유충 제외

def crop_pad_224(img, box, margin=0.10, size=224):
    import cv2
    H, W = img.shape[:2]; x1, y1, x2, y2 = box; w, h = x2 - x1, y2 - y1
    x1, y1 = max(0, int(x1 - w*margin)), max(0, int(y1 - h*margin)); x2, y2 = min(W, int(x2 + w*margin)), min(H, int(y2 + h*margin))
    native = img[y1:y2, x1:x2]; s = size / max(native.shape[:2])
    r = cv2.resize(native, (max(1, int(native.shape[1]*s)), max(1, int(native.shape[0]*s))), interpolation=cv2.INTER_AREA)
    out = np.zeros((size, size, 3), np.uint8); oy, ox = (size - r.shape[0])//2, (size - r.shape[1])//2; out[oy:oy+r.shape[0], ox:ox+r.shape[1]] = r
    return out, native

def write_stats(out_dir, matched, total):
    rate = matched / max(1, total); p = Path(out_dir) / "stats.json"
    p.write_text(json.dumps({"matched": matched, "total": total, "match_rate": rate, "warning": rate < 0.5}, indent=2), encoding="utf-8"); return p
```
CLI: `--manifest training/split_manifest.json --weights-A runs/yolo/v0.2.0-stage1A/weights/best.pt --weights-B ... --out crops/` — fold A 이미지는 weights-B로, fold B는 weights-A로 예측(conf 0.15, imgsz 1024, max_det 1500); golden·cal-A·cal-B 이미지는 `--fold all` 모델로 예측. 외부 데이터(Task 4)는 GT 박스로 크롭하되 같은 `crop_pad_224` 적용, `source` 열로 구분. 크롭 PNG는 gitignore.

- [ ] **Step 4: PASS → Step 5: `tasks.py crops` → 학습 박스 실행, `stats.json` `match_rate` 기록 → Step 6: 커밋** `feat(ai): out-of-fold 예측 박스 기반 Stage-2 크롭 추출`

---

### Task 9: Stage-2 학습·보정·ONNX — `train_stage2.py`

**Files:**
- Create: `apps/ai/training/train_stage2.py`
- Create: `apps/ai/training/configs/stage2.yaml`
- Create(학습 후): `apps/ai/training/configs/vdi.yaml`
- Test: `apps/ai/app/tests/unit/test_train_stage2.py`

**Interfaces:**
- Produces: `phone_degrade(img224: np.ndarray, rng, lo_px:int, hi_px:int=265) -> np.ndarray`; `fit_platt(logits, y) -> (a, b)`; `choose_tau(p_calA, y_calA, target_fpr=0.01) -> float`; `measure_rates(p_calB, y_calB, tau) -> (tpr, fpr)`; `export_onnx(model, path)` → 출력 2개 `logit`, `featmap`. `vdi.yaml`:
```yaml
version: v0.2.0
tau: 0.62
tpr: 0.91
fpr: 0.009
corrected: true          # tpr - fpr >= 0.5
platt: {a: 1.13, b: -0.42}
thresholds: {elevated: 3.0, high: 10.0}
quality: {blur_laplacian_min: 100, exposure_mean: [40, 215]}
capture_floor_px_per_mm: null   # Gate 0 후 기록
```

- [ ] **Step 1: 테스트**

```python
# apps/ai/app/tests/unit/test_train_stage2.py
import numpy as np
from training.train_stage2 import phone_degrade, fit_platt, choose_tau, measure_rates
def test_phone_degrade_shape_and_range():
    rng = np.random.default_rng(0); out = phone_degrade(np.full((224, 224, 3), 128, np.uint8), rng, lo_px=90)
    assert out.shape == (224, 224, 3) and out.dtype == np.uint8
def test_platt_recovers_scale_and_bias():
    rng = np.random.default_rng(1); z = rng.normal(0, 3, 4000); y = (rng.random(4000) < 1/(1+np.exp(-(0.5*z - 1)))).astype(int)
    a, b = fit_platt(z, y); assert abs(a - 0.5) < 0.1 and abs(b + 1) < 0.25
def test_tau_hits_target_fpr_and_rates():
    rng = np.random.default_rng(2); y = np.r_[np.zeros(2000), np.ones(200)]; p = np.r_[rng.beta(2, 8, 2000), rng.beta(8, 2, 200)]
    tau = choose_tau(p, y, 0.01); tpr, fpr = measure_rates(p, y, tau)
    assert fpr <= 0.012 and tpr > 0.5
def test_onnx_two_outputs(tmp_path):
    import torch, onnxruntime as ort
    from training.train_stage2 import build_model, export_onnx
    m = build_model(pretrained=False); p = export_onnx(m, tmp_path / "s2.onnx")
    s = ort.InferenceSession(str(p), providers=["CPUExecutionProvider"])
    assert [o.name for o in s.get_outputs()] == ["logit", "featmap"]
```

- [ ] **Step 2: 실패 확인 → Step 3: 구현** (핵심부)

```python
# apps/ai/training/train_stage2.py
from __future__ import annotations
import numpy as np, torch, torch.nn as nn
from pathlib import Path

def phone_degrade(img, rng, lo_px, hi_px=265):
    import cv2
    tgt = int(rng.integers(lo_px, hi_px + 1)); k = int(rng.choice([0, 3, 5])); x = img
    if k: x = cv2.GaussianBlur(x, (k, k), 0)                                   # 광학 블러
    small = cv2.resize(x, (tgt, tgt), interpolation=cv2.INTER_AREA)            # 폰 스케일로 축소
    small = np.clip(small.astype(np.float32) + rng.normal(0, rng.uniform(1, 6), small.shape), 0, 255).astype(np.uint8)  # 센서 노이즈
    sharp = cv2.addWeighted(small, 1.5, cv2.GaussianBlur(small, (0, 0), 1.0), -0.5, 0)  # ISP 언샤프
    ok, buf = cv2.imencode(".jpg", sharp, [cv2.IMWRITE_JPEG_QUALITY, int(rng.integers(50, 96))]); jpg = cv2.imdecode(buf, 1)
    return cv2.resize(jpg, (224, 224), interpolation=cv2.INTER_LINEAR)

def fit_platt(logits, y):
    from sklearn.linear_model import LogisticRegression
    lr = LogisticRegression(C=1e6).fit(np.asarray(logits).reshape(-1, 1), y); return float(lr.coef_[0][0]), float(lr.intercept_[0])

def choose_tau(p, y, target_fpr=0.01):
    neg = np.sort(np.asarray(p)[np.asarray(y) == 0]); return float(neg[int(np.ceil((1 - target_fpr) * len(neg))) - 1])

def measure_rates(p, y, tau):
    p, y = np.asarray(p), np.asarray(y); pred = p > tau
    return float(pred[y == 1].mean()), float(pred[y == 0].mean())

class Stage2(nn.Module):
    def __init__(self, pretrained=True):
        super().__init__()
        from torchvision.models import shufflenet_v2_x1_0, ShuffleNet_V2_X1_0_Weights
        b = shufflenet_v2_x1_0(weights=ShuffleNet_V2_X1_0_Weights.IMAGENET1K_V1 if pretrained else None)
        self.features = nn.Sequential(b.conv1, b.maxpool, b.stage2, b.stage3, b.stage4, b.conv5)
        self.fc = nn.Linear(1024, 1)
    def forward(self, x):
        f = self.features(x)                       # (B,1024,7,7)
        return self.fc(f.mean((2, 3))).squeeze(1), f

def build_model(pretrained=True) -> nn.Module: return Stage2(pretrained)

def export_onnx(model: nn.Module, path: Path) -> Path:
    model.eval(); dummy = torch.zeros(1, 3, 224, 224)
    torch.onnx.export(model, dummy, str(path), input_names=["image"], output_names=["logit", "featmap"], opset_version=17,
                      dynamic_axes={"image": {0: "b"}, "logit": {0: "b"}, "featmap": {0: "b"}})
    return path
```
학습 루프: `crops.csv`에서 split ∈ {train, external_train}; `WeightedRandomSampler`(클래스 역빈도 × 소스별 양성 prior 균등화 — 소스 s의 양성 가중치를 `1/(P_s(y=1))`로); 손실 `BCEWithLogitsLoss`(가중 없음), label smoothing 0.05; AdamW 3e-4 cos, 50 ep, patience 10(val AUROC); 증강 `--degrade {none|<lo_px>}` + flip·±15° 회전·밝기/대비 ±0.3·CLAHE p0.3·약한 원근 ≤10°. 학습 후 cal-A 크롭으로 `fit_platt`·`choose_tau`, cal-B로 `measure_rates` → `configs/vdi.yaml`(`corrected = tpr - fpr >= 0.5`), ECE(15-bin)·AUROC를 `eval_history/v0.2.0-stage2.json`에. `tasks.py train-stage2 --degrade none` / `--degrade 90`.

- [ ] **Step 4: PASS → Step 5: 학습 박스 실행(Gate 0용 `none` 먼저, Task 11 후 최종) → `vdi.yaml`·`eval_history/v0.2.0-stage2.json` 커밋 → Step 6: 커밋** `feat(ai): Stage-2 ShuffleNet 학습·Platt·τ·TPR/FPR·ONNX(2 outputs)`

---

### Task 10: VDI 수식 모듈 `app/services/vdi.py` (평가·서빙 공용)

**Files:**
- Create: `apps/ai/app/services/vdi.py`
- Modify: `apps/ai/requirements.txt` (`scipy>=1.11`, `pyyaml` 확인)
- Test: `apps/ai/app/tests/unit/test_vdi.py`

**Interfaces:**
- Produces:
```python
@dataclass
class VdiConfig: tau: float; tpr: float; fpr: float; corrected: bool; elevated: float = 3.0; high: float = 10.0
def load_vdi_config(path: Path) -> VdiConfig
def rogan_gladen(raw_pct: float, cfg: VdiConfig) -> float          # clip [0,100]; corrected=False 또는 tpr-fpr<0.5 면 raw
def jeffreys_ci(k: int, n: int) -> tuple[float, float]              # % 단위
def corrected_ci(k: int, n: int, cfg: VdiConfig) -> tuple[float, float]  # 끝점 사상, 하한 0 floor, 상한 ≥ raw 상한
def display(v: float) -> str                                        # Decimal ROUND_HALF_UP 1자리
def tier_from_display(s: str, cfg: VdiConfig, bee_total: int, quality_ok: bool) -> str
def aggregate(counts: list[tuple[int, int]], cfg: VdiConfig, quality_ok: bool = True) -> dict
```

- [ ] **Step 1: 테스트**

```python
# apps/ai/app/tests/unit/test_vdi.py
import math
from app.services.vdi import VdiConfig, rogan_gladen, jeffreys_ci, corrected_ci, display, tier_from_display, aggregate
CFG = VdiConfig(tau=0.6, tpr=0.90, fpr=0.01, corrected=True)
def test_display_rounding_boundaries():
    assert display(2.949) == "2.9" and display(2.95) == "3.0" and display(9.95) == "10.0" and display(10.0) == "10.0"
def test_tier_half_open_from_display():
    t = lambda s: tier_from_display(s, CFG, bee_total=300, quality_ok=True)
    assert t("2.9") == "low" and t("3.0") == "elevated" and t("9.9") == "elevated" and t("10.0") == "high"
    assert tier_from_display("50.0", CFG, bee_total=0, quality_ok=True) == "insufficient"
    assert tier_from_display("50.0", CFG, bee_total=10, quality_ok=False) == "insufficient"
def test_rogan_gladen_guard():
    bad = VdiConfig(tau=0.5, tpr=0.55, fpr=0.10, corrected=False)
    assert rogan_gladen(7.0, bad) == 7.0
    assert math.isclose(rogan_gladen(7.0, CFG), (7 - 1) / (0.90 - 0.01))
def test_healthy_hive_ci_not_collapsed():
    lo, hi = corrected_ci(0, 300, CFG); raw_lo, raw_hi = jeffreys_ci(0, 300)
    assert lo == 0.0 and hi >= raw_hi > 0
def test_aggregate_sums_counts_not_percentages():
    r = aggregate([(1, 40), (9, 900)], CFG)     # 10/940 = 1.064% raw
    assert math.isclose(r["raw"], 10 / 940 * 100) and r["tier"] == "low" and r["bee_total"] == 940
```

- [ ] **Step 2: 실패 확인 → Step 3: 구현**

```python
# apps/ai/app/services/vdi.py
"""VDI(가시 감염 지수) 수식 — 평가(training/eval_e2e.py)와 서빙(계획 2 two_stage_engine)이 공유."""
from __future__ import annotations
from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
import yaml
from scipy.stats import beta

@dataclass
class VdiConfig:
    tau: float; tpr: float; fpr: float; corrected: bool; elevated: float = 3.0; high: float = 10.0

def load_vdi_config(path: Path) -> VdiConfig:
    d = yaml.safe_load(path.read_text(encoding="utf-8"))
    return VdiConfig(d["tau"], d["tpr"], d["fpr"], bool(d["corrected"]), d["thresholds"]["elevated"], d["thresholds"]["high"])

def _usable(cfg: VdiConfig) -> bool: return cfg.corrected and (cfg.tpr - cfg.fpr) >= 0.5

def rogan_gladen(raw_pct: float, cfg: VdiConfig) -> float:
    if not _usable(cfg): return raw_pct
    return min(100.0, max(0.0, (raw_pct - cfg.fpr * 100) / (cfg.tpr - cfg.fpr)))

def jeffreys_ci(k: int, n: int) -> tuple[float, float]:
    if n == 0: return (0.0, 100.0)
    lo = 0.0 if k == 0 else float(beta.ppf(0.025, k + 0.5, n - k + 0.5)) * 100
    hi = 100.0 if k == n else float(beta.ppf(0.975, k + 0.5, n - k + 0.5)) * 100
    return (lo, hi)

def corrected_ci(k: int, n: int, cfg: VdiConfig) -> tuple[float, float]:
    lo, hi = jeffreys_ci(k, n)
    if not _usable(cfg): return (lo, hi)
    f = lambda v: (v - cfg.fpr * 100) / (cfg.tpr - cfg.fpr)
    return (max(0.0, f(lo)), min(100.0, max(hi, f(hi))))   # 상한은 raw 상한 이상 — [0,0] 붕괴 방지

def display(v: float) -> str:
    return str(Decimal(repr(float(v))).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))

def tier_from_display(s: str, cfg: VdiConfig, bee_total: int, quality_ok: bool) -> str:
    if bee_total == 0 or not quality_ok: return "insufficient"
    v = Decimal(s)
    if v < Decimal(str(cfg.elevated)): return "low"
    if v < Decimal(str(cfg.high)): return "elevated"
    return "high"

def aggregate(counts: list[tuple[int, int]], cfg: VdiConfig, quality_ok: bool = True) -> dict:
    k, n = sum(c[0] for c in counts), sum(c[1] for c in counts)
    raw = (k / n * 100) if n else 0.0; v = rogan_gladen(raw, cfg); lo, hi = corrected_ci(k, n, cfg); d = display(v)
    return {"bee_infested": k, "bee_total": n, "raw": raw, "vdi": v, "vdi_display": d, "sampling_ci95": (lo, hi),
            "tier": tier_from_display(d, cfg, n, quality_ok)}
```

- [ ] **Step 4: PASS → Step 5: 커밋** `feat(ai): vdi.py — Rogan–Gladen·Jeffreys·display 반올림·tier·집계`

---

### Task 11: Gate 0(b) — px/mm별 recall 곡선

**Files:**
- Create: `apps/ai/training/gate0_pxmm.py`
- Test: `apps/ai/app/tests/unit/test_gate0.py`

**Interfaces:**
- Produces: `scale_for_target(native_px_per_mm: float, target: float) -> float`; `simulate_px_per_mm(native_crop: np.ndarray, native_px_per_mm: float, target: float, rng) -> np.ndarray(224)`; CLI `--weights runs/stage2/v0.2.0-native/best.pt --crops crops/ --split golden --targets 22,15,12,9` → `eval_history/v0.2.0-gate0.json` (`{"22": {"recall":..,"specificity":..}, ...}`). 71667 native px/mm = 22.

- [ ] **Step 1: 테스트**

```python
# apps/ai/app/tests/unit/test_gate0.py
import numpy as np
from training.gate0_pxmm import scale_for_target, simulate_px_per_mm
def test_scale_for_target(): assert scale_for_target(22, 11) == 0.5
def test_simulate_returns_224():
    out = simulate_px_per_mm(np.full((300, 260, 3), 100, np.uint8), 22, 9, np.random.default_rng(0)); assert out.shape == (224, 224, 3)
```

- [ ] **Step 2: 실패 확인 → Step 3: 구현** — `scale = target / native`; native 크롭의 긴 변을 `int(round(long * scale))`로 고정해 Task 9의 `phone_degrade(img224, rng, lo_px=tgt, hi_px=tgt)`를 호출(입력은 `crop_pad_224` 결과 224). CLI는 golden 크롭에 대해 target별 recall/specificity를 `vdi.yaml`의 τ로 계산.
- [ ] **Step 4: PASS → Step 5: 학습 박스 실행** → 결과 JSON 커밋 → 붕괴 지점(recall이 22 대비 −15%p 이상 떨어지는 첫 target)을 `vdi.yaml.capture_floor_px_per_mm`와 스펙 §13에 기록. 12MP 한 컷(≈9)이 미달이면 "반 소비판" 가이드가 기본; 반 소비판(≈18)도 미달이면 **중단하고 보고**(스펙 §7).
- [ ] **Step 6: 커밋** `feat(ai): Gate 0 px/mm recall 곡선`

---

### Task 12: 평가 — Stage-2 분리 지표 · 지름길 프로브 · 합성 e2e · 단일 스테이지 베이스라인

**Files:**
- Create: `apps/ai/training/eval_stage2.py`
- Create: `apps/ai/training/eval_e2e.py`
- Create: `apps/ai/training/configs/baseline_single.yaml`
- Modify: `apps/ai/training/eval.py` (1-class, mAP `conf=0.001`, recall 게이트)
- Test: `apps/ai/app/tests/unit/test_eval_e2e.py`

**Interfaces:**
- Produces: `eval_stage2.py --weights --crops --split golden` → `eval_history/v0.2.0-stage2.json`: `{"overall":{recall,specificity,auroc,ece}, "by_source":{...}, "by_device":{...}, "by_colony":{...}, "size_only_auroc":..., "source_probe_acc":..., "lodo":{...}}`; `build_pseudo_frames(crops_df, targets=(0,2,5,12,20), n_bees=300, n_frames=40, seed) -> list[dict]` (`{"target","paths","labels"}`); `tier_agreement(truth, pred) -> float`; `trivial_baseline(truth) -> float`; `eval_e2e.py` → `eval_history/v0.2.0-e2e.json`: `{"tier_confusion":..., "tier_agreement":..., "trivial_all_low":..., "healthy_frames_under_3_pct":..., "single_stage_baseline":{...}}`.

- [ ] **Step 1: 테스트**

```python
# apps/ai/app/tests/unit/test_eval_e2e.py
import pandas as pd
from training.eval_e2e import build_pseudo_frames, tier_agreement, trivial_baseline
def _df():
    return pd.DataFrame([{"path": f"p{i}", "label": int(i < 60), "colony": "g1"} for i in range(1000)])  # 6% 양성
def test_pseudo_frames_hit_targets():
    frames = build_pseudo_frames(_df(), targets=(0, 5, 12), n_bees=300, n_frames=5, seed=0)
    assert len(frames) == 15 and all(len(f["labels"]) == 300 for f in frames)
    for f in frames: assert abs(sum(f["labels"]) / 3 - f["target"]) <= 0.5
def test_trivial_baseline_and_agreement():
    truth = ["low"] * 7 + ["elevated"] * 2 + ["high"]
    assert trivial_baseline(truth) == 0.7 and tier_agreement(truth, truth) == 1.0
```

- [ ] **Step 2: 실패 확인 → Step 3: 구현**

```python
# apps/ai/training/eval_e2e.py (핵심)
import numpy as np, pandas as pd
def build_pseudo_frames(df: pd.DataFrame, targets=(0, 2, 5, 12, 20), n_bees=300, n_frames=40, seed=42) -> list[dict]:
    rng = np.random.default_rng(seed); pos = df[df.label == 1].path.to_numpy(); neg = df[df.label == 0].path.to_numpy(); out = []
    for t in targets:
        k = int(round(t * n_bees / 100))
        for _ in range(n_frames):
            ps = list(rng.choice(pos, k, replace=True)) if k else []; ns = list(rng.choice(neg, n_bees - k, replace=True))
            out.append({"target": t, "paths": ps + ns, "labels": [1] * k + [0] * (n_bees - k)})
    return out
def tier_agreement(truth, pred): return float(np.mean([a == b for a, b in zip(truth, pred)]))
def trivial_baseline(truth): return float(np.mean([t == "low" for t in truth]))
```
실행부: 각 프레임의 크롭에 Stage-2(ONNX)를 돌려 `k = Σ(p>τ)`, `aggregate([(k, n)], cfg)`로 tier → 진짜 tier(target 기준)와 혼동행렬; `healthy_frames_under_3_pct` = target 0 프레임 중 `vdi < 3` 비율. 단일 스테이지 베이스라인: `baseline_single.yaml`(YOLO11s 2-class `bee_normal`/`bee_varroa`, imgsz 1024, 같은 fold)로 학습 후 golden 이미지에서 `bee_varroa 탐지 수 / 전체 벌 탐지 수`를 raw로 `aggregate`에 넣어 같은 지표 산출. `eval_stage2.py`: `sklearn.metrics`(recall/specificity@τ, AUROC, ECE 15-bin) + `groupby(source/device/colony)` + 크기·종횡비 로지스틱(`[native_w, native_h, w/h]`, 5-fold AUROC) + 소스 프로브(penultimate 임베딩 → `LogisticRegression` 5-fold acc) + leave-one-device-out.

- [ ] **Step 4: PASS → Step 5: 학습 박스 실행 → `eval_history/v0.2.0-{stage1,stage2,e2e,gate0}.json` 커밋 → 게이트 판정을 `docs/05-implementation/2026-XX-XX-v020-training.md`에 표로 기록(스펙 §7 기준 통과/실패, 사소 베이스라인 병기).**
- [ ] **Step 6: 커밋** `feat(ai): Stage-2 분리 지표·지름길 프로브·합성 e2e·단일 스테이지 베이스라인 평가`

---

## Self-Review (작성 후 점검)

1. **스펙 커버리지**: §5.2 xyxy(T3) · §5.1 데이터 역할·음성 규칙·cal 반분·golden 동결(T4~T6, T8) · §5.3 디스크/manifest/Windows(T1~T3, T5) · §6 레시피·재현성(T7, T9) · §7 Gate 0·Stage-1·Stage-2·e2e·베이스라인 게이트(T11, T12) · `vdi.yaml`·VDI 수식(T9, T10). §9 8~10단계(서빙·스키마·앱)는 계획 2. **갭**: 71488 스키마 파서는 다운로드 후 필드 확인이 필요해 T7 Step 6에 조건부로 둠; EV2 JSONL 필드명도 T4에서 확인 후 fixture 갱신.
2. **플레이스홀더**: "다운로드 후 확인" 2건은 외부 데이터 포맷 미확인에 따른 것으로, 확인 절차와 대상 함수를 명시함.
3. **타입 일관성**: `Box` 튜플(T3) ↔ `parse_annotations` 소비처(T5 `load_items_from_aihub`, T8 `gts`); `VdiConfig`(T10) ↔ `vdi.yaml` 스키마(T9); `aggregate` 반환 키 ↔ `eval_e2e`(T12); `phone_degrade` 시그니처(T9) ↔ `simulate_px_per_mm`(T11); `build_model/export_onnx`(T9) ↔ `test_onnx_two_outputs`.
4. **Review Focus**: 1→T3 `test_parse_skips_missing_area`, 2→T5 `test_manifest_colony_disjoint`, 3→T8 `test_match_rate_recorded`, 4→T10 `test_rogan_gladen_guard`, 5→T10 `test_display_rounding_boundaries`. 모두 배치됨.
