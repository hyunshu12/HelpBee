# 2026-06-08 — HelpBee YOLO v0.1.0 varroa 검출기 베이스라인 (GO)

> PR: (이 PR) · 브랜치: `docs/*` → `develop` · 머지일: (TBD)
>
> ⚠️ 본 문서는 v0.1.0 사이클 전체의 **통합 구현 기록**이다. 기존 분절된 기록인 **#14**(HP 스윕 + copy_paste no-op 정정)와 **#15**(golden 평가 + sign-off)를 이 문서가 **흡수·대체**한다. 두 PR의 산출물(`AIHUB_71667.md` 정정, `eval_history/v0.1.0.json` 등)은 여기에 통합 요약된다.

---

## 범위 (Scope)

AI Hub 71667(꿀벌 질병 진단 이미지) 기반 **단일 스테이지 3-class YOLOv11s @ imgsz 640** varroa 검출기 v0.1.0을 HP 스윕 → 200-epoch 본학습 → golden holdout 평가 → ONNX export·CPU latency 측정 → S3 업로드 → sign-off까지 한 사이클로 완성하고, 그 결과를 **GO**로 확정한다. (모델·imgsz 잠금은 ADR-0001 / 2026-06-05.)

---

## 산출물 (Deliverables)

### 모델 가중치 (git 미커밋 — `.gitignore` 정책)

| 산출물 | 경로 | 크기 |
|---|---|---|
| best.pt | `apps/ai/training/runs/yolo/v0.1.0-baseline/weights/best.pt` | **19M** |
| best.onnx | `apps/ai/training/runs/yolo/v0.1.0-baseline/weights/best.onnx` | **37M** |

> 학습 산출물(`*.pt`/`*.onnx`/`runs/`)은 git에 커밋하지 않는다(apps/ai/CLAUDE.md §12). git log 확인 결과 두 파일 모두 커밋 이력 없음 — 정책 준수.

### S3 업로드

- **버킷**: `s3://helpbee-models/yolo/v0.1.0/` — `best.pt`, `best.onnx`, `metadata.json`
- 버킷 신규 생성: **versioning + SSE(AES256) + public-access-block** 적용 (infra/CLAUDE.md §9, §15 정책 일치)
- ⚠️ 업로드에 **AWS ROOT 액세스 키**(account `491919374695`)가 사용됨 → 후속 작업에서 회전 필수 (아래 후속 작업 참조)

### 평가·설정·스윕 아티팩트 (git)

| 파일 | 설명 |
|---|---|
| `apps/ai/training/datasets/_final_config.yaml` | 본학습 최종 config (200ep) |
| `apps/ai/training/datasets/_sweep_results.json` | 6개 스윕 config별 metric |
| `apps/ai/training/datasets/_sweep_best.json` | 스윕 기계적 best(sgd-largebatch) |
| `apps/ai/training/runs/yolo/v0.1.0-baseline/results.csv` | 200ep 학습 곡선 (best=epoch 180) |
| `apps/ai/training/runs/yolo/v0.1.0-baseline/weights/eval_golden.json` | golden 300장 평가 결과 |

### 흡수한 분절 기록 (PR #14 / #15)

- **#14** `docs(ai): v0.1.0 HP 스윕 결과 기록 + copy_paste no-op 정정` (open, head `docs/ai-hp-sweep-v010`, base `develop`) — `AIHUB_71667.md` §7/§11의 copy_paste 관련 서술 정정 포함
- **#15** `docs(ai): v0.1.0 golden 평가 기록 + CONDITIONAL-GO sign-off` (open, head `docs/ai-v010-eval-history`, base `develop`) — `eval_history/v0.1.0.json` + sign-off

---

## 결과 (Results)

### 1) HP 스윕 (6 config, varroa_ap50 정렬)

분할 검증(split-val) 기준. 굵게 = 선택(cls-heavy), 별표 = 기계적 best(varroa_ap50 단일 최댓값).

| config | overrides 요지 | varroa_ap50 | varroa_R | normal_ap50 | mAP50 | mAP50-95 |
|---|---|---|---|---|---|---|
| sgd-largebatch * | SGD, lr0 0.01, cos_lr | **0.9904** | 0.9875 | 0.7244 | 0.8884 | 0.7681 |
| recall-aggressive | copy_paste 0.5, box 6.0, close_mosaic 5 | 0.9894 | 0.9833 | 0.8353 | 0.9353 | 0.7811 |
| **cls-heavy** ✅ | **cls 1.5, dfl 1.5** | **0.9862** | 0.9866 | **0.858** | **0.9335** | 0.7794 |
| copypaste-heavy | copy_paste 0.6, mixup 0.2, scale 0.6 | 0.7261 | 0.9875 | 0.6256 | 0.7545 | 0.6255 |
| baseline | (없음) | 0.7009 | 0.9833 | 0.5996 | 0.7558 | 0.6385 |
| reg-generalize | weight_decay 0.001, copy_paste 0.4, degrees 15 | 0.6964 | 0.9571 | 0.5695 | 0.7226 | 0.6053 |

- **기계적 best = sgd-largebatch** (varroa_ap50 0.9904, 단일 지표 최고).
- **채택 = cls-heavy.** 근거는 아래 「핵심 결정/발견」 참조 (분모 보호 = normal_ap50 0.858로 6개 중 최고).

### 2) 최종 config (본학습)

`_final_config.yaml` 핵심 값:

| 항목 | 값 |
|---|---|
| model / pretrained | `yolo11s.yaml` / `yolo11s.pt` |
| imgsz | 640 |
| batch | 64 |
| epochs / patience | 200 / 30 |
| optimizer / lr0 | AdamW / 0.001 |
| cls / dfl (스윕 채택 override) | **1.5 / 1.5** |
| mixup | 0.2 |
| close_mosaic | 20 |
| copy_paste | 0.3 (기본값 잔류 — **실효 no-op**, 아래 참조) |
| hsv_h | 0.015 |
| seed / deterministic | 42 / true |

### 3) 본학습 (split-val, results.csv best row)

- 총 **200 epochs**, fitness(0.1·mAP50 + 0.9·mAP50-95) 기준 **best = epoch 180**
- **mAP50 = 0.9647**, **mAP50-95 = 0.9047**

### 4) Golden holdout 평가 (300장, eval_golden.json)

> golden 셋은 학습/aug에서 영구 격리(leak-free 검증 완료). split-val보다 분포 외(out-of-distribution) 성격이 강해 수치가 더 보수적이다.

| 지표 | 값 |
|---|---|
| mAP@0.5 | **0.9159** |
| mAP@0.5:0.95 | **0.8474** |
| infestation_rate MAE | **0.141** (%p, 300장) |

클래스별 P/R:

| 클래스 | Precision | Recall |
|---|---|---|
| bee_with_varroa | 0.9808 | 0.95 |
| bee_normal | 0.9169 | 0.7122 |
| bee_other_disease | 0.8830 | 0.9225 |

**회귀 게이트(CLAUDE.md §13 / apps/ai/CLAUDE.md):** mAP50 ≥ 0.85 **AND** mAP50-95 ≥ 0.60 → golden 기준 `0.9159 ≥ 0.85` & `0.8474 ≥ 0.60` → **PASS**.

### 5) CPU(ONNX) latency

| 환경 | P50 | P95 |
|---|---|---|
| 1-thread (≈ Fargate 1 vCPU) | 245 ms | 263 ms |
| 16-core | 52 ms | 68 ms |

게이트 `CPU 추론 P95 < 2s` → **PASS** (최악 케이스 263 ms).

### 6) Sign-off

- 초기 판정 **CONDITIONAL-GO** (latency 미측정 조건부) → CPU latency 측정 완료 후 **GO**.
- **최종 판정: GO** — golden 회귀 게이트 PASS + latency 게이트 PASS.

---

## 핵심 결정/발견

### A) cls-heavy 선택 근거 — "분모 보호"

기계적 best는 varroa_ap50 단일 최댓값인 sgd-largebatch(0.9904)였으나, **cls-heavy를 본학습 config로 채택**했다. 핵심 risk 지표 `infestation_rate = varroa / (전체 벌) × 100`은 **분모에 bee_normal 검출 품질이 직접 들어간다**. cls-heavy는 **normal_ap50 = 0.858로 6개 config 중 최고**(sgd-largebatch는 0.7244에 그침)이며 mAP50(0.9335)도 사실상 최상위라 분모 안정성과 종합 성능을 동시에 확보한다. varroa_ap50은 0.9862로 기계적 best와 0.4%p 차에 불과해 분자 손실은 미미하다. (드래프트에 언급된 결정 워크플로 ID는 코드베이스에서 확인되지 않아 본 기록에서는 인용하지 않으며, 선택 근거는 위 metric으로 정당화된다.)

### B) copy_paste no-op — augmentation 실효 0

`_final_config.yaml`에 `copy_paste: 0.3`이 남아 있으나 **이 데이터셋에서는 아무 효과가 없다.** varroa-v1 라벨은 **bbox-only(5필드: class cx cy w h)** 이고 segment가 없다 → ultralytics 8.3.253의 `CopyPaste.__call__`은 `segments == 0`일 때 조기 반환한다. 따라서 응애 인스턴스 imbalance(2.4%) 대응은 **copy_paste가 아니라 mixup(0.2)**으로 이루어졌다. `AIHUB_71667.md` §7/§11의 "Copy-Paste 필수" 서술은 이 발견에 따라 정정됨(PR #14에 반영). v0.1.x 데이터 확장 시 oversampling 또는 segment 라벨 추가를 검토한다.

### C) bimodal-golden MAE의 한계

`infestation_rate_mae = 0.141`은 **per-mite(응애 개체) 오차가 아니라 이미지 단위 infestation_rate(%) 지표의 MAE**다. 71667 라벨은 응애 자체 bbox가 없어(Q3=B, "감염된 벌 영역") per-mite 카운팅이 불가능하다. 또한 golden 셋은 응애 100 + 정상 200의 **bimodal 구성**이라 중간 감염률 구간 표본이 비어 있어, tier 경계(3%/10%) 부근의 flip 위험을 이 단일 평균값이 충분히 포착하지 못한다. 베타에서 실측 VMIR(sugar-roll/alcohol-wash) 라벨로 회귀 보정 + per-subset MAE가 필요하다.

---

## 검증 (Verification)

- **golden isolation (leak-free):** golden 300장은 split 이전 단계에서 영구 격리(`golden_holdout.py`), 학습/aug 미포함 확인. golden 라벨이 5필드 bbox-only임도 직접 확인.
- **회귀 게이트:** golden eval_golden.json의 mAP50/mAP50-95가 `≥0.85 / ≥0.60` 양 조건 충족 → PASS. (split-val best epoch 180도 0.9647/0.9047로 동일 게이트 통과.)
- **latency 게이트:** ONNX 1-thread P95 263 ms < 2s → PASS. Fargate 1 vCPU 환경을 1-thread로 근사.
- **스윕/본학습 수치:** `_sweep_results.json`(6 config), `_sweep_best.json`(sgd-largebatch), `results.csv`(epoch 180 fitness 최고), `eval_golden.json` 파일 직접 대조로 확인.
- **S3 무결성:** `aws s3 ls s3://helpbee-models/yolo/v0.1.0/`로 best.pt(18.3 MiB)/best.onnx(36.6 MiB)/metadata.json(1.7 KiB) 업로드 직접 확인. 버킷 versioning Enabled + AES256 + public-block.

---

## 후속 작업 (Follow-up)

- 🔴 **(보안 최우선) AWS ROOT 키 회전** — account `491919374695`. 업로드에 root 키 사용됨. 즉시 회전 + 이후 OIDC/IAM task role로 전환 (infra/CLAUDE.md §8, §19).
- 🟠 **`helpbee-models` 버킷 Terraform 코드화** — 콘솔/CLI로 생성된 버킷을 `infra/terraform/modules/s3`로 import 또는 재정의 (infra/CLAUDE.md §6, §9, §19-8 "콘솔 자원 즉시 코드화").
- 🟠 **5% canary 배포** — `YOLO_MODEL_VERSION=v0.1.0` blue-green canary 5% → golden mAP / P95 latency / FP·FN 1주 모니터 → 100% promote (apps/ai/CLAUDE.md §8-7).
- 🟡 **v0.1.1 개선 항목**
  - bee_normal **recall 0.7122** 개선 (분모 안정성 직접 영향)
  - **per-subset MAE + tier-flip** 분석 추가 (bimodal-golden 한계 해소)
  - **외부/현장 데이터 기반 field-rate golden** 교체 (71667 내부 분리는 분포 동질 → 일반화 평가 약함)

---

## 참조

- **권위 가이드:** [apps/ai/CLAUDE.md](../../apps/ai/CLAUDE.md) — §8 YOLO 파이프라인, §13 회귀 게이트
- **ADR:** [docs/01-development/adr/ADR-0001-yolo-engine-architecture.md](../01-development/adr/ADR-0001-yolo-engine-architecture.md) — v0.1.0 = 단일 스테이지 3-class YOLOv11s @ 640 잠금
- **데이터셋:** [apps/ai/training/datasets/AIHUB_71667.md](../../apps/ai/training/datasets/AIHUB_71667.md) — Q3=B 라벨 특성, infestation_rate 정의, copy_paste 정정
- **흡수 PR:** #14 (HP 스윕 + copy_paste 정정), #15 (golden 평가 + sign-off) — 본 문서가 통합
- **인프라 정책:** [infra/CLAUDE.md](../../infra/CLAUDE.md) — §8 시크릿, §9 S3, §19 AI 작업 규칙
