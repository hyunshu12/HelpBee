# HelpBee YOLO 2-Stage 모델 설계 — v0.1.0

> 설계 결정 일자: 2026-05-07 | Owner: AI팀 | 참고: Lee et al. JKSCI 2024.10
> Status: APPROVED for implementation | Target: 2026-06 MVP 베타

---

## 0. TL;DR

- **무엇**: 사진 한 장 → "벌 검출(Stage 1) → 마리별 응애 감염 분류(Stage 2)" → `infected_bee_rate` 기반 위험도. OpenAI Vision과 dual-engine 병행.
- **무엇을 따르는가**: Lee et al. JKSCI 2024.10 의 two-stage 골격. detector는 YOLOv11s (논문 v8-n 대신), 2단계 학습은 **Zenodo → 71667 fine-tune** 으로 한국 도메인 적응.
- **운영 형상**: 단일 FastAPI 컨테이너, Stage1 → Stage2 순차, **CPU + ONNX INT8 양자화 필수**. `uvicorn --workers 2`, per-worker lazy-load, `Semaphore(2)`.
- **차별점**: 71667 라벨이 "감염된 벌 영역"이라 표준 VMIR 불가 → `infected_bee_rate` 별도 정의. 임계값 (3% / 10%)은 차용하되 베타 vet 데이터로 보정.
- **핵심 위험**: Stage1·Stage2 오류 곱셈 (recall 0.85 × 0.91 ≈ 0.77 end-to-end) + 베타 도메인 시프트 + PII. infested recall 게이트 + vet 보정 + EXIF/얼굴 redaction으로 다층 방어.

---

## 1. 아키텍처 개요

```
[client image]
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│  apps/ai (FastAPI, uvicorn workers=2)                  │
│                                                         │
│  POST /analyze/yolo                                     │
│      │                                                  │
│      ▼                                                  │
│  preprocess (EXIF strip, GPS strip, HEIC→sRGB, ≤1024)   │
│      │                                                  │
│      ▼                                                  │
│  Stage 1: bee_detector (YOLOv11s, 640, ONNX-INT8)       │
│      → boxes [(cls, conf, xyxy), ...]                   │
│      │                                                  │
│      ▼                                                  │
│  class-agnostic NMS dedup (iou=0.5)                     │
│      → top-K (MAX_BEES_PER_REQUEST=64)                  │
│      │                                                  │
│      ▼                                                  │
│  crop & reflect-pad (224×224)                           │
│      │                                                  │
│      ▼                                                  │
│  Stage 2: infested_clf (YOLOv11s-cls, 224, batch=32)    │
│      → P(infested) per bee                              │
│      │                                                  │
│      ▼                                                  │
│  aggregate → infected_bee_rate, tier, risk_score        │
│      │                                                  │
│      ▼                                                  │
│  AnalysisResponse                                       │
└─────────────────────────────────────────────────────────┘
```

**책임 분리**

| 레이어 | 책임 | 비책임 |
|---|---|---|
| Stage 1 detector | 벌 위치 검출 (worker/queen 학습 후 추론은 **class-agnostic 통합**) | 응애 판정 X |
| Stage 2 classifier | 마리별 binary 감염 판정 | 카운팅 X (Stage1이 마리 수 결정) |
| `services/risk.py` | rate → tier/score, recommendations 매핑 | 모델 호출 X |
| router | 요청 검증, 엔진 호출, 비용 콜백 | 모델 직접 호출 X |

---

## 2. 학습 스펙

### 2.1 Stage 1 — Bee Detector

| 항목 | 값 | 근거 |
|---|---|---|
| 모델 | YOLOv11s | s가 n 대비 mAP +3~5pp, INT8 후 latency 흡수 가능 |
| 입력 | 640×640 | 논문 표준, P2 head 미사용 (71488 bbox 분포 medium~large) |
| 데이터 | AI Hub 71488 (worker / queen, ~5k) | 논문과 동일 데이터셋, 한국 도메인 |
| 클래스 | 2 (worker=0, queen=1) | **추론 시 class-agnostic NMS 통합** (3.6 참조) |
| 분할 | per_colony_time_block, val 20% | colony 누수 방지 |
| Augmentation | hflip, rotate ±15°, hsv (h=0.015, s=0.7, v=0.4), scale 0.5 | 논문 simple aug 재현 |
| OFF | mosaic / mixup / copy_paste | 논문 미사용, 베이스라인 단순화 |
| 옵티마이저 | SGD, lr0=0.01, momentum=0.937, weight_decay=5e-4 | Ultralytics 기본 |
| 에포크 | 100 + early stop patience 15 | val mAP plateau |
| 배치 | 16 (Colab A100) | OOM 마진 |

**학습 목표**: mAP@0.5 ≥ 0.70 (논문 0.701 동등), recall@0.5 ≥ 0.80.
**프로모션 게이트**: 4.4 참조 (학습 목표보다 엄격).

### 2.2 Stage 2 — Infested Classifier

| 항목 | 값 |
|---|---|
| 모델 | YOLOv11s-cls (binary head: infested / uninfested) |
| 입력 | 224×224, ImageNet 정규화 |
| Phase 1 데이터 | Zenodo VarroaDataset (10k, balanced) |
| Phase 2 데이터 | Phase 1 + 71667 single-bee crop (도메인 적응) |
| **학습 Augmentation** | RandomResizedCrop(224, scale=(0.8,1.0)), hflip(p=0.5), color jitter (brightness=0.2, contrast=0.2, saturation=0.2), RandomErasing(p=0.1). **Geometric distortion(rotation>15°, shear, perspective) 금지** — 응애 형태/위치 단서 손실 |
| Phase 1 학습 | 50 epoch, SGD lr0=0.01 |
| Phase 2 학습 | 50 epoch, lr0=0.001 (Phase 1의 1/10), Phase 1 weight 로드 |
| 클래스 가중치 | 71667 추가 후 imbalance 보정 (`class_weights=[w_uninf, w_inf]`) |
| 손실 | CrossEntropy + label smoothing 0.05 |

**학습 목표 (training target)**:
- Phase 1 acc ≥ 0.91 (논문 동등)
- Phase 2 한국 도메인 acc ≥ 0.88, **infested recall ≥ 0.92** (학습 종료 기준)

**프로모션 게이트 (4.4)**: infested recall ≥ 0.95 — 학습 목표보다 3pp 높음. 학습 후 τ 보정으로 recall 끌어올림 (precision trade-off 감수).

### 2.3 71667 single-bee crop 추출 절차

```python
# training/data/aihub_to_stage2_crops.py (의사코드)
MIN_AREA_RATIO = 0.01
MAX_AREA_RATIO = 0.30

def extract_crops(json_path, out_dir):
    img, ann = load_71667(json_path)
    H, W = img.shape[:2]
    img_area = H * W
    for a in ann["annotations"]:
        x, y, w, h = a["bbox"]
        ratio = (w * h) / img_area
        if not (MIN_AREA_RATIO <= ratio <= MAX_AREA_RATIO):
            continue
        cat = a["category_id"]
        # 1·5(응애) → infested, 0·4(정상) + 2·3·6(기타질병) → uninfested
        label = "infested" if cat in (1, 5) else "uninfested"
        crop = pad_and_resize(img, (x, y, w, h), size=224, pad="reflect")
        save(out_dir / label / f"{json_path.stem}_{a['id']}.jpg", crop)
```

**출력 구조 (3-way split: train / val / cal — leakage 방지)**

```
training/datasets/stage2-71667-v0.1.0/
├── train/{infested,uninfested}/   # 70%
├── val/{infested,uninfested}/     # 15% — early stop, hparam selection
└── cal/{infested,uninfested}/     # 15% — τ 보정 전용, 다른 두 split과 colony-disjoint
```

**3-way 분할 규칙**: per_colony_time_block 으로 colony를 train/val/cal에 disjoint 할당. 동일 colony가 두 split에 등장하면 안 됨. cal은 early stop·hparam 선택에 절대 사용 X.

### 2.4 τ_infested 보정 절차

기본 τ=0.5는 부트스트랩 전용. Phase 2 종료 후 보정 필수:

1. **별도 cal split** (2.3 참조, ≥ 2,000 crop, balanced)에서 P(infested) 분포 산출. **cal은 train/val과 colony-disjoint, early stop·hparam tuning에 미사용** (leakage 방지).
2. **목표 FPR = 5%** 가 되는 τ 탐색: `τ* = quantile of P(infested|negative) at 0.95`.
3. 같은 τ에서 measured recall, precision, F1 기록.
4. `training/configs/risk.yaml` 에 핀:

```yaml
stage2:
  tau_infested: 0.62              # 보정값 (예시)
  calibration:
    target_fpr: 0.05
    measured_fpr: 0.048
    measured_recall: 0.93
    measured_precision: 0.91
    val_set: stage2-cls-cal-v0.1.0
    n_negatives: 1024
    n_positives: 1024
    pinned_at: "2026-05-30"
```

5. τ는 **모델 버전과 1:1 페어링**. 새 cls 모델 배포 시 재보정 필수, PR description에 위 표 첨부.

---

## 3. 추론 파이프라인 + 위험도 산출

### 3.1 추론 흐름

```python
# app/services/yolo_engine.py (의사코드)
async def analyze_yolo(image_bytes: bytes, include_raw: bool = False) -> AnalysisResponse:
    img = preprocess(image_bytes)               # EXIF+GPS strip, HEIC→sRGB, ≤1024px
    async with YOLO_SEMAPHORE:                  # asyncio.Semaphore(2) per worker
        det = stage1.predict(img, imgsz=640, conf=0.25, iou=0.5)
        # class-agnostic NMS: worker/queen 통합, iou=0.5 dedup
        boxes = nms_class_agnostic(det.boxes, iou=0.5)

        truncated = False
        if len(boxes) > MAX_BEES_PER_REQUEST:    # 64
            boxes = sorted(boxes, key=lambda b: b.conf, reverse=True)[:64]
            truncated = True

        crops = [pad_and_resize(img, b.xyxy, 224, pad="reflect") for b in boxes]
        probs = []
        for chunk in batched(crops, 32):
            probs.extend(stage2.predict_proba(chunk)[:, INFESTED_IDX])

    n_bees = len(boxes)
    if n_bees == 0:
        return graceful_null("no_bee_detected")  # ci95=None, rate=None

    infested_mask = [p > tau_infested for p in probs]
    n_infested = sum(infested_mask)
    queen_count = sum(1 for b in boxes if b.cls == 1)
    queen_fraction = queen_count / n_bees       # monitoring signal (3.6)

    rate = 100.0 * n_infested / n_bees
    score, tier = piecewise_risk(rate)
    ci_low, ci_high = wilson_ci(n_infested, n_bees) if n_bees >= 1 else (None, None)

    return AnalysisResponse(
        risk_score=score, tier=tier,
        n_bees_detected=n_bees, n_infested=n_infested,
        infected_bee_rate=rate,
        infected_bee_rate_ci95=(ci_low, ci_high),
        low_sample_size=(n_bees < 30),
        mean_conf_all=mean(probs),
        mean_conf_infested=mean([p for p, m in zip(probs, infested_mask) if m]) if n_infested else None,
        queen_fraction=queen_fraction,
        recommendations=recommend(tier, low_sample_size=(n_bees < 30)),
        stage1_version=STAGE1_VER, stage2_version=STAGE2_VER,
        pipeline_version=f"{STAGE1_VER}+{STAGE2_VER}",
        tau_infested=TAU_INFESTED, latency_ms=ms,
        raw_payload={"truncated": truncated, "boxes": boxes_dict, "probs": probs} if include_raw else None,
    )
```

### 3.2 risk_score piecewise 공식

71667 라벨의 "감염된 벌 영역" 정의 → `infected_bee_rate` (%). 구간 내부는 **선형 보간**. 경계는 **left-closed right-open** (마지막 구간 제외).

| rate 구간 | score 공식 |
|---|---|
| `[0, 3)`   | `30 · (rate / 3)` |
| `[3, 10)`  | `30 + 40 · ((rate - 3) / 7)` |
| `[10, 30)` | `70 + 30 · ((rate - 10) / 20)` |
| `[30, 100]` | `100` (saturation) |

**경계 단위 테스트 필수** (4.4 게이트):

| rate | 기대 score | tier |
|---|---|---|
| 0 | 0 | safe |
| 2.999 | 29.99 | safe |
| 3.0 | 30 | watch |
| 9.999 | 69.994 | watch |
| 10.0 | 70 | danger |
| 29.999 | 99.998 | danger |
| 30.0 | 100 | danger |
| 100 | 100 | danger |

`risk.yaml`:

```yaml
risk:
  measure: infected_bee_rate
  semantic_note: "71667 label = infected bee region, NOT mites/100bees (standard VMIR)"
  vmir_calibration_pending: true       # 베타 vet 데이터 입력 후 보정
  bands:
    - {min: 0,   max: 3,   score_min: 0,   score_max: 30,  tier: safe}
    - {min: 3,   max: 10,  score_min: 30,  score_max: 70,  tier: watch}
    - {min: 10,  max: 30,  score_min: 70,  score_max: 100, tier: danger}
    - {min: 30,  max: 100, score_min: 100, score_max: 100, tier: danger}
  interpolation: linear_left_closed_right_open  # 마지막 구간 [30, 100]은 양쪽 닫힘
```

### 3.3 AnalysisResponse 스키마

```python
# app/schemas/analysis.py
from typing import Literal, Optional, Tuple
from pydantic import BaseModel, Field

class AnalysisResponse(BaseModel):
    # 핵심
    risk_score: Optional[int] = Field(default=None, ge=0, le=100)  # n=0이면 null
    tier: Literal["safe", "watch", "danger"]

    # 카운팅 / rate
    n_bees_detected: int
    n_infested: int
    infected_bee_rate: Optional[float] = None                # %, n=0이면 null
    infected_bee_rate_ci95: Tuple[Optional[float], Optional[float]] = (None, None)
    low_sample_size: bool                                    # n_bees < 30
    queen_fraction: Optional[float] = None                   # 모니터링용

    # confidence (3-field split)
    mean_conf_all: Optional[float] = None                    # n=0이면 null
    mean_conf_infested: Optional[float] = None               # n_infested=0이면 null

    # UX
    recommendations: list[str]                               # 한국어, ≤5개

    # 운영 메타 (version split)
    stage1_version: str                                      # "det-v0.1.0"
    stage2_version: str                                      # "cls-v0.1.0"
    pipeline_version: str                                    # "det-v0.1.0+cls-v0.1.0"
    tau_infested: float

    latency_ms: int
    cost_estimate_usd: Optional[float] = None                # YOLO는 None
    error_reason: Optional[str] = None                       # graceful null 시 채움

    # 디버그 (gated)
    raw_payload: Optional[dict] = None                       # ?include_raw=true 시만
```

**Wilson CI edge cases**:
- `n_bees == 0` → `ci95 = (None, None)`, `rate = None`, `risk_score = None`, `tier = "watch"`
- `n_bees < 3` → wide-band CI 그대로 보고 (보정 X), `low_sample_size=True`
- `n_infested == 0` → CI lower bound = 0
- `n_infested == n_bees` → CI upper bound = 1.0

### 3.4 Recommendations 한국어 enum 매핑

```python
# app/services/risk.py
RECOMMENDATIONS = {
    "safe": [
        "현재 응애 감염 징후가 낮습니다. 정기 점검(주 1회)을 유지하세요.",
        "벌통 환기 상태와 수분 공급을 확인하세요.",
    ],
    "watch": [
        "감염 의심 개체가 관찰됩니다. 7일 이내 sugar-roll 또는 alcohol-wash 실측을 권장합니다.",
        "drone-comb trap 설치를 고려하세요.",
        "다음 주 같은 위치를 재촬영하여 변화 추이를 확인하세요.",
    ],
    "danger": [
        "응애 감염 위험이 높습니다. 즉시 옥살산 또는 포름산 처리를 검토하세요.",
        "수의사 또는 양봉 컨설턴트 상담을 권장합니다.",
        "인접 벌통도 함께 점검하세요 (전파 위험).",
    ],
}
LOW_SAMPLE_NOTE = "검출된 벌 수가 30마리 미만입니다. 결과 해석에 주의하고 재촬영을 권장합니다."

def recommend(tier: str, low_sample_size: bool) -> list[str]:
    out = list(RECOMMENDATIONS[tier])
    if low_sample_size:
        out.insert(0, LOW_SAMPLE_NOTE)
    return out[:5]
```

**i18n 사전 준비 (Day 1, 비용 거의 0)**: 위 dict를 `app/locales/ko.yaml` 로 외부화하고 enum id로 키 (`safe.0`, `watch.1` ...). 렌더러는 `Accept-Language` 헤더를 읽어 향후 `en.yaml` 추가 시 자동 분기. v0.1.0은 ko만 제공.

### 3.5 Failure modes 표

| 상황 | 처리 |
|---|---|
| Stage 1: 0개 검출 | `tier="watch"`, `risk_score=null`, `infected_bee_rate=null`, `ci95=(null,null)`, `error_reason="no_bee_detected"`, recommendations에 "재촬영 권장" |
| Stage 2: 모든 P가 NaN/추론 실패 | graceful null (200), `error_reason="stage2_failure"` |
| 입력 이미지 손상 / 디코드 실패 | 400 + ErrorEnvelope |
| 10MB 가드 후 초과 | 400 |
| Stage 1 모델 미로드 (S3 다운 실패) | **fallback chain** (3.6 참조). 끝까지 실패 시 503 |
| Stage 2 INT8 파일 손상 (sha256 불일치) | FP32 onnx로 자동 fallback, `int8_fallback_total` 메트릭 increment |
| `n_bees > 64` (truncated) | top-64 conf 사용, `raw_payload.truncated=true` |
| `n_bees < 30` (low sample) | 결과는 반환, `low_sample_size=true` + 재촬영 권고 prepend |
| HEIC 디코드 실패 | 400 |
| 월 비용 한도 초과 | YOLO 영향 없음 (OpenAI 단독), `/analyze/dual` 별도 가드 (3.6) |
| `YOLO_DEVICE=cuda` but CUDA unavailable | **CPU로 자동 fallback**, `device_fallback=1` 메트릭, critical 로그. 컨테이너 crash 금지 (canary 롤백 보호) |

### 3.6 동시성 / 메모리 / 엣지 케이스

| 항목 | 값 / 처리 |
|---|---|
| `uvicorn --workers` | **2** 기본 (`UVICORN_WORKERS` env). MVP 단일 컨테이너 |
| 모델 로딩 | per-worker **lazy-load** (첫 요청에 로드, 이후 메모리 상주) |
| 동시 호출 제한 | `asyncio.Semaphore(2)` per worker on `/analyze/yolo` |
| 메모리 가드 | `MAX_BEES_PER_REQUEST = 64`, Stage 2 batch chunk = 32 |
| Truncate 정책 | det confidence DESC, top-64. `raw_payload.truncated=true` |
| **Class-agnostic NMS** | Stage 1 inference 시 worker/queen 통합 후 iou=0.5 NMS. queen FP가 n_bees 부풀리지 않도록. `queen_fraction` 메트릭으로 모니터 |
| Edge bbox crop padding | bbox가 이미지 경계 닿으면 **reflect padding** 으로 224×224 채움 |
| HEIC | `pillow-heif` 디코드 후 **명시적 sRGB 변환** (`ImageCms` profile or `convert("RGB")` + ICC strip) |
| EXIF | orientation 적용 후 **strip + GPS strip** (PII) |
| `YOLO_DEVICE` 변경 | **컨테이너 재시작 필수**. cuda 미가용 시 CPU fallback (3.5) |
| **부팅 시 모델 무결성 체크** | sha256 검증 → **fallback chain**: `best.int8.onnx` → `best.onnx` (FP32) → readiness probe 실패 → 503 |
| 가중치 캐시 | `/var/cache/helpbee/yolo/{stage}/v{X.Y.Z}/` (Docker volume), miss 시 S3 다운 |

### 3.7 Latency 목표 표

CPU x86_64 8 vCPU, ONNX Runtime + INT8 양자화. **두 가지 케이스로 분리**:

**Case A — typical (n_bees=30)**:

| 단계 | P50 | P95 |
|---|---|---|
| preprocess | 50ms | 120ms |
| Stage 1 (640, INT8) | 250ms | 450ms |
| crop + pad (30개) | 30ms | 60ms |
| Stage 2 (224, 30개, batch 32) | 200ms | 400ms |
| aggregate | 10ms | 30ms |
| **end-to-end** | **≤ 600ms** | **≤ 1100ms** |

**Case B — max load (n_bees=64, batch 32×2)**:

| 단계 | P50 | P95 |
|---|---|---|
| preprocess | 50ms | 120ms |
| Stage 1 | 250ms | 450ms |
| crop + pad (64개) | 60ms | 120ms |
| Stage 2 (224, 64개, **2× batch 32**) | 380ms | 760ms |
| aggregate | 10ms | 30ms |
| **end-to-end** | **≤ 750ms** | **≤ 1500ms** |

→ 회귀 게이트(4.4)는 **Case A P95 ≤ 1100ms** + **Case B P95 ≤ 1500ms** 두 메트릭 모두 측정.
INT8 미적용 시 Stage 2 latency ~3×. **양자화 필수**, FP32 fallback 시 별도 P95 추적 (운영 가능 범위 < 2000ms).

---

## 4. 버전관리 / 배포 / 테스트 / 마일스톤

### 4.1 SemVer (stage 독립)

- `det-vMAJOR.MINOR.PATCH` (Stage 1)
- `cls-vMAJOR.MINOR.PATCH` (Stage 2)
- PATCH = 데이터 추가만 / MINOR = 하이퍼·아키 변경 / MAJOR = 클래스·태스크 변경
- 두 stage 독립 버전업. `pipeline_version = stage1_version + "+" + stage2_version` (display only).

### 4.2 S3 weight management

```
s3://helpbee-models/yolo/
├── det/v0.1.0/
│   ├── best.pt
│   ├── best.onnx              ← FP32 (fallback)
│   ├── best.int8.onnx         ← 운영 추론용
│   └── metadata.json
└── cls/v0.1.0/
    ├── best.pt
    ├── best.onnx
    ├── best.int8.onnx
    └── metadata.json
```

**metadata.json 필수 필드**: `stage`, `version`, `train_dataset_versions`, `train_commit_sha`, `wandb_run_url`, `golden_metrics{mAP50, infested_recall, accuracy}`, `latency_p95_cpu_ms`, `tau_infested` (cls만), `sha256{onnx, int8_onnx, pt}`, `int8_calibration_set_hash`, `created_at`, `released_by`.

env: `STAGE1_VERSION=det-v0.1.0`, `STAGE2_VERSION=cls-v0.1.0`. 부팅 시 두 버킷 다운 + sha256 검증.

### 4.3 Canary deployment (stage 독립)

- Stage 1 / Stage 2 **각각 5% canary → 7일 모니터 → 100% promote**.
- 동시에 둘 다 갈아엎지 않는다 (실패 원인 분리 불가). 한 stage씩 순차.
- 롤백: env 한 줄 + K8s rollout. 직전 2버전 S3 보존 (90일).
- Greenlight: golden mAP/acc 비회귀, infested recall ≥ 0.95, P95 latency baseline+10%, error rate 비스파이크, 베타 FN report 0.

### 4.4 회귀 게이트 (CI 차단)

| 항목 | 기준 | 측정 셋 |
|---|---|---|
| Stage 1 mAP@0.5 | ≥ 0.70 (이전 ≥ 동등) | 71488 val + golden 사진 |
| Stage 2 acc | ≥ 0.88 (Phase 2 후) | stage2-cls-val |
| **Stage 2 infested recall (promotion gate)** | **≥ 0.95 at pinned τ** | stage2-cls-cal |
| Stage 2 uninfested recall | ≥ 0.85 | stage2-cls-val |
| End-to-end `infected_bee_rate` MAE | ≤ 3.0pp | golden 300장 |
| Tier flip count (safe ↔ danger 직접 전이) | **0** | golden |
| **Latency P95 Case A (n=30)** | ≤ 1100ms | bench fixture 50장 |
| **Latency P95 Case B (n=64)** | ≤ 1500ms | bench fixture 20장 |
| ONNX INT8 acc 손실 vs FP32 | ≤ 1.5pp | stage2-cls-val |

> 학습 목표(2.2 Phase 2 recall ≥ 0.92) vs 프로모션 게이트(≥ 0.95) 관계: 학습 후 τ 보정으로 recall 향상. τ 보정 후에도 0.95 미달이면 모델 재학습 또는 데이터 보강.

**테스트 매트릭스 (CI 필수)**

| 종류 | 항목 |
|---|---|
| Unit | piecewise 경계값 8개 (3.2 표), Wilson CI edge `n ∈ {0, 1, 3, 30}`, HEIC→sRGB ICC strip, EXIF GPS strip 검증, INT8↔FP32 parity 100 fixture |
| Integration | uvicorn workers=2 + lazy-load + Semaphore(2) contention, fallback chain (int8→fp32→503), HEIC end-to-end, large-image (n_bees=64) 메모리 |
| Regression | golden 300장 + checked-in 기대 JSON, infested recall, MAE, tier flip 0 |
| Smoke (배포 전) | `/analyze/yolo` 50req 1분 부하, P95 측정, error rate 0% |

PR 본문에 회귀 diff 표 첨부 필수.

### 4.5 Cross-domain eval slices

| Slice | 출처 | 목적 |
|---|---|---|
| `golden-71667` | 300 holdout (현재) | 한국 comb-light 베이스라인 |
| `golden-zenodo` | 100 from VarroaDataset | 글로벌 일반화 |
| `golden-beta` (Phase 2, 6월~) | 50+ 베타 사진 + vet 라벨 | 진짜 분포 |
| `device-holdout` | 71667 unseen capture device | 하드웨어 일반화 |

각 슬라이스에서 회귀 게이트 모두 통과 요구. 단일 슬라이스 평균만 보지 않는다.

### 4.6 프로덕션 모니터링 + 알람

| 메트릭 | 임계 | 알람 |
|---|---|---|
| `/analyze/yolo` P95 latency | > 1.5s 5분 | PagerDuty warn |
| Stage 1 검출 0개 비율 | > 20% 일간 | Slack #ai-alerts |
| `low_sample_size=true` 비율 | > 30% 일간 | Slack |
| `truncated=true` 비율 | > 5% 일간 | Slack (MAX_BEES 재검토) |
| **`queen_fraction` 평균** | > 5% 일간 | Slack (paper queen acc 48% → false-queen 검토) |
| `mean_conf_all` 분포 KS test | p < 0.01 vs 30d baseline | 도메인 시프트, 재학습 트리거 |
| Dual-engine tier mismatch (YOLO vs OpenAI) | > 15% 주간 | AI팀 리뷰 |
| `int8_fallback_total` | > 0/일 | Slack (모델 무결성 의심) |
| `device_fallback_total` | > 0/일 | Slack (CUDA 의도 vs 실제) |
| OOM / 모델 미로드 | 1회 | PagerDuty critical |
| **`/analyze/dual` 일일 호출 수** | > 1,000 | Slack (어드민 sweep 의심) |
| **`/analyze/dual` OpenAI 비용 누적** | > 80% of `OPENAI_DUAL_MONTHLY_BUDGET_USD` | Slack |

**`/analyze/dual` 보호**:
- Rate limit: 100 req/hour per admin token
- 별도 예산 env: `OPENAI_DUAL_MONTHLY_BUDGET_USD=100` (메인 예산과 분리)
- 초과 시 503 BUDGET_EXCEEDED — 메인 `/analyze` 영향 X

### 4.7 재학습 루프 + 베타 vet 워크플로

**feedback 레코드 스키마** (`feedback_queue` 테이블):

| 필드 | 타입 | 비고 |
|---|---|---|
| `id` | uuid | |
| `analysis_id` | uuid | 원 분석 결과 참조 |
| `image_id` | uuid | S3 키 (PII redaction 후) |
| `user_label` | enum {agree, disagree_fp, disagree_fn, unsure} | 양봉가 신고 |
| `vet_label` | enum {infested, uninfested, ambiguous, rejected} | vet 검토 후 |
| `vet_id` | str | vet 식별 |
| `vet_reviewed_at` | timestamp | |
| `sugar_roll_vmir` | float | nullable, 실측 VMIR |
| `bucket` | enum {train, golden, cal} | 재학습 분배 |
| `reject_reason` | enum {blurry, pii, off_target, duplicate} | nullable |

**vet SLA**: 신고 접수 ~ vet 검토 72시간 이내. 미달 시 PagerDuty.
**reject 기준**: blurry (Laplacian variance < 임계), PII (얼굴/손/이름 라벨 잔존), off-target (벌 없음), duplicate (perceptual hash).

**bucket 할당 정책**:
- 신규 양봉가 사진 70% → train, 20% → golden (분기별 갱신), 10% → cal (τ 재보정)
- 동일 colony 사진은 한 bucket에만 (leakage 방지)
- vet_label=ambiguous 또는 rejected는 학습 제외

**자동화 단계**:

| 트리거 | 조치 | 승인자 |
|---|---|---|
| 신규 vet-라벨 100건 누적 (주간 cron) | 영향받은 stage PATCH 자동 재학습 | 자동 → golden 통과 시 staging |
| KS drift 알람 (30d) | 수동 조사 | ML eng |
| 베타 새 batch ≥ 1k | MINOR 재학습 | ML eng + vet sign-off (golden-beta) |
| Class change | MAJOR + schema migration | tech lead |

자동 promote staging→canary: golden + cross-domain 게이트 통과 필수.
canary→100%: 7일 green window + 사람 ack.
GPU 학습 인스턴스 자동 terminate (`gcloud ... delete --quiet`) 보장.

### 4.8 마일스톤 (데이터 다운로드가 critical path)

| 주차 | Stage 1 | Stage 2 | 인프라 |
|---|---|---|---|
| **5월 W1** | 71488 다운 + 라이선스 + YOLO 변환 | Zenodo VarroaDataset 다운 + CC BY 검증 | S3 `yolo-det/`, `yolo-cls/` provision; **PII redaction 모듈** (얼굴/손 blur, EXIF/GPS strip) |
| **5월 W2** | det-v0.1.0 학습 (A100), golden mAP 리포트 | 71667 응애 crop + Zenodo Phase 1 학습, acc ≥ 0.91 | `/analyze/yolo` glue + class-agnostic NMS + ONNX FP32 export |
| **5월 W3** | mAP ≥ 0.70 튜닝 | Phase 2 fine-tune + τ 보정 | metadata.json + sha256 boot 검증 + INT8 양자화 + parity test |
| **5월 W4** | Cross-domain 리포트 | Cross-domain + Case A/B latency bench | `/analyze/dual` 어드민 UI + rate limit + dual budget guard; staging canary |
| **6월 W1** | prod canary 5% | prod canary 5% | Prometheus 대시보드 + 알람; **vet 라벨러 1명 계약 확정** |
| **6월 W2 (베타)** | 100% if green | 100% if green | feedback_queue + bucket 할당 + 주간 cron 무장 |
| **6월 W3-4** | patch v0.1.1 (베타 사진 통합) | patch v0.1.1 + τ 재보정 | golden-beta 50장 vet 라벨 완료 |

---

## 5. 핵심 리스크 + 미해결 항목

| 리스크 | 영향 | 완화 |
|---|---|---|
| **베타 도메인 시프트** | 한국 양봉가 스마트폰 사진 부재. mAP 급락 가능 | 베타 1주차 200+ 실사진 수집 *후* 정확도 발표. 골든 즉시 추가, 주 1회 patch |
| **Two-stage failure 곱셈** | recall 0.85×0.91 ≈ 0.77 → FN 23% | infested recall 게이트 0.95, e2e MAE 게이트, vet 보정 |
| **71488 라이선스 (내국인)** | 국제 협업 시 사용 불가 | EOW까지 AI lead 접근 확인. 막히면 71667 detection-only fallback (정확도 ceiling 문서화) |
| **vet 라벨러 확보** | VMIR 실측 비용 미산정 (50~100만원/월) | 6월 W1까지 1명 계약 확정, sugar-roll 프로토콜 표준화 |
| **`infected_bee_rate` ≠ VMIR** | 임계값 3%/10% 의미 불일치 | 베타 vet 데이터로 회귀 보정, R²≥0.7 달성 후 v0.2.0 임계 재튜닝 |
| **PII (PIPA 위험)** | 양봉가 얼굴/손/이름 라벨 노출, EXIF GPS 누출 | (1) EXIF GPS strip 필수, (2) 얼굴/손 자동 blur (MediaPipe), (3) 학습용 90일 후 익명화/삭제, (4) 양봉가 동의서 |
| **GPU sweep 비용 폭주** | 월 5회 sweep ~$200-300 | spot 인스턴스 + 자동 terminate hook |
| **INT8 acc 손실 1.5pp 초과** | 운영 불가 | per-channel calibration 1k crop, FP32 fallback 항상 보존, parity CI |
| **CUDA 미가용 host crash-loop** | canary 롤백 차단 | `YOLO_DEVICE=cuda` + cuda 미가용 시 CPU 자동 fallback + 메트릭 (3.5) |
| **Stage 1 queen FP** | 논문 queen acc 48%, n_bees 부풀림 | class-agnostic NMS + queen_fraction 모니터 (>5% 알람) |
| **Wilson CI UX 혼란** | UX 부담 | 기본 UI 점추정만, admin/`?include_raw`에서만 |
| **/analyze/dual 비용 폭주** | 어드민 sweep으로 OpenAI 예산 침해 | rate limit 100/hr/token, 별도 `OPENAI_DUAL_MONTHLY_BUDGET_USD` |

---

## 6. v0.1.0 → v0.2.0 트리거

**승급 (모두 충족)**

1. 베타 양봉가 사진 ≥ 1,000장 + vet 실측 VMIR 라벨 ≥ 100건
2. 베타 슬라이스 Stage 2 infested recall ≥ 0.92, e2e MAE ≤ 5pp
3. `infected_bee_rate ↔ VMIR` 회귀 R² ≥ 0.7, 임계값 재튜닝 PR 머지
4. Case A INT8 P95 ≤ 800ms (CPU 8 vCPU)
5. Dual-engine tier match (YOLO vs OpenAI) ≥ 80%

**재검토 (즉시 재설계)**

- Stage 2 infested recall < 0.85 (베타 슬라이스, 2주 연속)
- mean_conf_all KS p < 0.001 (도메인 시프트)
- OpenAI vs YOLO tier mismatch > 30% (2주 연속)
- 71488 / 71667 / Zenodo 라이선스 변경
- v0.2.0 후보 비교 실험: P2 head, multi-class detector (응애 자체 bbox), single-stage 재통합

---

## 부록: 적용된 사전 리뷰 fix 추적

| # | 이슈 | 적용 위치 |
|---|---|---|
| BLOCKER 1 | recall 학습목표 vs 게이트 모순 | §2.2 + §4.4 (관계 명시) |
| BLOCKER 2 | P95 at MAX_BEES=64 무효 | §3.7 Case A/B 분리 |
| BLOCKER 3 | τ cal set leakage | §2.3 3-way split, §2.4 cal-disjoint |
| BLOCKER 4 | piecewise 경계 연속성 미정 | §3.2 left-closed-right-open + 단위 테스트 표 |
| BLOCKER 5 | Wilson CI n=0 | §3.3 edge case, §3.5 graceful null |
| MAJOR 6 | queen 클래스 추론 동작 | §1, §3.1, §3.6 class-agnostic NMS + queen_fraction 모니터 |
| MAJOR 7 | INT8 corruption fallback | §3.6 sha256 + fallback chain |
| MAJOR 8 | CUDA 미가용 boot loop | §3.5, §3.6, §5 CPU fallback + 메트릭 |
| MAJOR 9 | vet 워크플로 미정 | §4.7 record 스키마 + SLA + reject + bucket |
| MAJOR 10 | PII | §4.8 마일스톤 (5월 W1), §5 |
| MAJOR 11 | /analyze/dual 비용 ceiling | §4.6 rate limit + 별도 예산 |
| MINOR 12 | i18n | §3.4 ko.yaml 외부화 |
| MINOR 13 | 테스트 매트릭스 | §4.4 unit/integration/regression/smoke |
| MINOR 14 | Stage 2 augmentation | §2.2 명시 |
