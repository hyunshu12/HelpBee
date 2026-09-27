# 2026-09-25 — HelpBee AI v0.2.0 2-stage Training 단계 실행 기록 (Stage-1 PASS / Stage-2 v2 FAIL → E3 최종 PASS)

> PR: (미생성) · 브랜치: `feature/ai-two-stage-redesign-spec` · 계획 1 task 12b 문서
>
> 근거: SDD 원장 `.superpowers/sdd/2026-09-23-ai-two-stage-plan1-data-training/progress.md`(5b-2 이후),
> `apps/ai/training/eval_history/v0.2.0-*.json`, `apps/ai/training/configs/vdi.yaml`,
> `apps/ai/training/data/frozen_colonies.json`, 스펙 `docs/superpowers/specs/2026-09-22-ai-two-stage-redesign-design.md` §7.
> Validation 단독 shakedown 산출물은 `eval_history/shakedown-*.json`이며 이 문서의 최종 수치가 아니다.

---

## 1. 요약

- **Stage-1(성충 1-class `bee` 검출)**: golden(296장, 응애 이미지 96장 포함)에서 mAP50 **0.986** / recall **0.961** → 게이트(mAP ≥0.85, recall ≥0.90) **PASS**.
- **Stage-2(크롭 응애 가시 분류)**: τ=0.472(cal_a FPR 1%)에서 cal-B TPR **0.272**, FPR **0.004** → TPR−FPR **0.27 < 0.5** → `corrected=false`. golden recall 0.18(기준 ≥0.90) → **게이트 FAIL**.
- 병목은 Stage-2 recall. 사용자 결정(2026-09-25 15:20)으로 **옵션 B — 스펙 변경 없이 Stage-2 v3 모델 개선 실험** 진행 중. E1/E2 결과와 τ 정책 분석상 **동작점 규칙(cal-A FPR 1%)이 구속 조건**이라는 결론 → τ 정책 변경(옵션 A)은 **사용자 결정 대기**.

## 2. 데이터

### 2.1 이미지·분할 (Training-phase refreeze, 1회 허용분)

- 71667 **Validation 31,095장** + **Training 서브셋 25,000장**(`aihub_subset`: TL.zip 스트리밍 인덱스 249,817 JSON → 응애 성충 이미지 4,081장 우선 + colony 층화 선택, 최소 JSON 라벨 + 선택 JPG만 추출) = 56,095장, 30 colonies.
- 동결 홀드아웃(`frozen_colonies.json`, 이후 **영구 동결**):

| 분할 | colonies | 응애 이미지 |
|---|---|---|
| golden | 001, 028, 022 | 96 (1분 dedupe 후; 1,295장 중복 제거) |
| cal_a | 002, 020 | 923 |
| cal_b | 010, 016 | 559 |
| train | 나머지 | 30,717장 (응애 1,734 / 성충 포함 15,503) |
| val | 시간 블록 꼬리 | 7,691장 (응애 6 — Stage-2 val은 VarroaDataset val 병용) |

- train-sub adult1 변환: 25,000장, bee 박스 84,792개(면적 교차검증 84,787/84,792), colony id가 Validation과 동일해 홀드아웃이 일관 적용됨.

### 2.2 Stage-2 크롭 (crops v2)

- 71667: GT 매칭률 0.977(97,218/99,494 성충 GT), **52,085 크롭**. 외부(VarroaDataset·EV2) 크롭 병합.
- VarroaDataset·EV2 크롭은 **이미지 전체를 크롭 박스로** 사용(원본이 벌 크롭).
- EV2 `label=1 & varroa_visible=False` 프레임은 **양성·음성 모두에서 제외**(Stage-2는 *가시* 응애 분류기 — ruling I2).

| 분할 | 크롭 | 양성 |
|---|---|---|
| train | 36,289 | 7,404 (71667 양성 ≈1,900, shakedown 176 대비 ≈10×) |
| val | 2,147 | 457 |
| cal_a | 7,784 | 1,009 |
| cal_b | 18,835 | 562 |
| golden | 817 | 110 |
| 평가 전용 | VarroaDataset test 3,408 (양성 942) / EV2 holdout 785 (양성 226) | |

## 3. 학습

### 3.1 Stage-1 v2 (YOLO, imgsz 1024)

| fold | train/val 이미지 | epochs | val mAP50-95 |
|---|---|---|---|
| A | 4,904 / 2,606 | 50 | 0.984 |
| B | 10,599 / 4,650 | 50 | 0.992 |
| all | 15,503 / 7,256 | **61/100에서 중단**(사용자 결정 2026-09-25 12:58, ~20 epoch부터 0.990 정체) → best.pt 사용 | 0.990 |

A/B는 out-of-fold 크롭 생성용이라 50 epoch로 축소. val은 동일 colony 시간 블록이라 낙관적 — 실제 게이트는 golden.

### 3.2 Stage-2 v2

- `shufflenet_v2_x1_0`, degrade none, 크기 지터 0.7–1.3(9c, 크기 지름길 완화), Windows `workers=0`, ~4 min/epoch.
- best epoch 1(val AUROC 0.962, VarroaDataset 지배), early stop 11. Platt a=0.492, b=−2.027, τ=0.4722(`target_fpr` 0.01, cal_a).

## 4. 게이트 (스펙 §7)

| 게이트 | 기준 | 측정 | 판정 |
|---|---|---|---|
| Stage-1 | mAP50 ≥0.85, recall ≥0.90 | mAP50 0.986, mAP50-95 0.800, P 0.955, R 0.961 (golden 296장) | **PASS** (밀집 폰 프레임 5장 recall 미측정) |
| Stage-2 | recall ≥0.90 & specificity ≥0.985 @τ | golden recall 0.182 / spec 0.989 / AUROC 0.856 / ECE 0.040; cal-B TPR 0.272 FPR 0.004 | **FAIL** |
| Stage-2 크기 베이스라인 | AUROC <0.7 | golden 0.79, EV2 0.85, VarroaDataset 0.50 | FAIL — 단, **데이터 속성**(GT 박스 크기로 프로브하므로 증강으로 바뀌지 않음; 모델 측 지름길 프로브 필요) |
| Stage-2 분리 보고 | 소스·기기·colony | 기기: 소문 recall 0.19 / 소비판 0.15; colony 001 0.19 · 022 0.25 · 028 0.00; LODO AUROC 0.75 / 0.69; 소스 선형 프로브 acc 1.0 | 보고 |
| Gate 0 (b) | recall 붕괴 지점 확정 | px/mm 22/15/12/9 → recall 0.20/0.20/0.21/0.17 (평탄 ≈0.2, `collapse_px_per_mm` null) | **판정 불가** (recall 자체가 낮아 무정보). (a)(c) 미실행 |
| e2e | tier 일치 ≥0.85 & 베이스라인 우세 | tier 일치 **0.425** vs 사소(전부 low) 0.40; VDI MAE 5.87(목표 20%에서 15.5 — 고감염 과소추정) | **FAIL** |
| e2e 0% 감염 | VDI<3 in ≥95% | **1.00** | PASS |
| 단일 스테이지 베이스라인 | 비교 | `single_stage_baseline: null` | **미실행** (실행 시에도 실제 golden 프레임 vs 의사-프레임이라 like-for-like 아님 — 참고용) |
| OOD | 보고만 | VarroaDataset test AUROC 0.958 / recall 0.146; EV2 holdout AUROC 0.930 / recall 0.044 / ECE 0.179 | 보고 |

## 5. shakedown(Validation 단독) vs v2

| 지표 | shakedown (degnone) | v2 |
|---|---|---|
| 71667 train 양성 크롭 | 176 | ≈1,900 |
| cal_a / cal_b AUROC | 0.699 / 0.722 | 0.806 / 0.831 |
| τ (cal_a FPR 1%) | 0.126 | 0.472 |
| cal-B TPR / FPR | 0.017 / 0.0006 | 0.272 / 0.004 |
| golden AUROC / recall@τ | 0.886 / 0.239 | 0.856 / 0.182 |
| VarroaDataset test AUROC / recall@τ | 0.948 / 0.001 | 0.958 / 0.146 |
| EV2 holdout AUROC / recall | 0.60 / 0.0 | 0.93 / 0.044 |
| golden size_only_auroc | 0.816 | 0.79 |

양성 10× 증가로 71667 cal AUROC는 +0.1 개선, cal-B TPR도 크게 올랐으나 게이트엔 한참 못 미침. val AUROC 기준 모델 선택이 VarroaDataset에 맞춰져 epoch 1에서 정점 — 71667과 불일치.

## 6. v3 실험 (옵션 B, 스펙 변경 없음)

| 실험 | 변경 | best ep | cal_a / cal_b AUROC | golden AUROC | τ | cal-B TPR / FPR | golden recall@τ | 비고 |
|---|---|---|---|---|---|---|---|---|
| E1 | v2 + 모델 선택을 cal_a AUROC로 | 3 | 0.807 / **0.848** | 0.874 | 0.429 | 0.046 / 0.0007 | 0.055 | Platt/τ가 선택 분할(cal_a)에 적합 — 약간 낙관적; cal_b 수치는 불편 |
| E2 | E1 + 320 px 크롭 | 8 | 0.824 / 0.812 | 0.849 | 0.488 | 0.269 / 0.0009 | 0.164 | VarroaDataset test recall 0.588, EV2 AUROC 0.90 |
| E3 | E2 + resnet18 | — | epoch 4 시점 cal_a 0.872 | — | — | — | — | **진행 중 / 추후 갱신** (~7.5 min/epoch) |

### τ 정책 분석 (scratch `tau_policy.py`, cal_a에 Platt 적합)

| τ 규칙 | v2 | E1 |
|---|---|---|
| cal_a FPR 1% (현 스펙) | τ 0.472 → cal-B TPR 0.272 / FPR 0.004 | τ 0.429 → cal-B 0.046 / 0.0007 |
| cal_a FPR 2% | 원장 미기재 | 원장 미기재 |
| cal_a FPR 5% | 원장 미기재 | 원장 미기재 |
| cal_a FPR 10% | τ 0.453 (cal-B FPR은 1.0–2.7% 범위) | τ 0.431 |
| **Youden (max TPR−FPR on cal_a)** | cal-B **0.568 / 0.067 → 0.501 (≥0.5)**; golden TPR 0.736 FPR 0.119 | cal-B 0.488 / 0.018 → 0.469; golden TPR 0.618 FPR 0.085 |

- 같은 τ에서 cal_b FPR이 cal_a FPR의 1/3~1/10 — colony 002/020 음성이 010/016보다 높게 점수화 → "cal-A FPR 1%" 규칙은 과보수적이고 colony 민감.
- AUROC ≈0.85에서 **모델 간 차이보다 동작점 규칙이 recall을 구속**한다.
- **결정 대기 — 옵션 A 권고**: τ = cal-A Youden(FPR 상한 예: ≤10%), cal-B로 TPR/FPR 측정, TPR−FPR ≥0.5이면 Rogan–Gladen 보정 허용(VDI 불편, CI 확대). cal 분할은 colony 다양화(현재 각 2개) 필요. 스펙 §3/§7 변경 사안이라 사용자 승인 전 미적용.

## 7. 운영 교훈

상세 절차는 [`apps/ai/training/data/DOWNLOAD.md`](../../apps/ai/training/data/DOWNLOAD.md).

- **aihubshell은 디스크 3×** 필요(download.tar + 분할 파트 + 병합 파일) 이고 서버가 파트를 **두 번 전송**할 수 있음(z01 tar 214 GB = 100 파트 ×2) → 자체 스트리밍 다운로더(`curl | tar -xO | head -c 100GiB`).
- **TL.zip은 풀지 않는다**(~620 GB JSON 예상) → python zipfile 스트리밍 인덱스 + `aihub_subset`으로 필요한 이미지만 추출. zip 내부엔 01./02. 접두 폴더가 없음 — 각각 이름 붙인 폴더로 해제.
- Windows schtasks: 한글 포함 ps1은 **UTF-8 BOM** 필수(PS5가 cp949로 파싱), 트리거는 시간 기반. 7z 출력은 **`-sccUTF-8`** 없으면 cp949라 목록 대조 0/25,000 실패.
- Stage-2 DataLoader는 Windows에서 **`workers=0`**(로컬 Dataset 클래스 pickling 불가).
- 원본 zip에 **0바이트 JPG 1장**(`C_008_016_20230919100028_001_008_001_002.jpg`) → `cv2.imdecode` 크래시 → `_imread`가 None 반환하도록 가드.
- 그 핫픽스가 정의되지 않은 `logger`를 참조해 NameError로 파이프라인 재실패 → **핫픽스 push 전 수정 모듈 import 경로를 한 번 실행**할 것.

## 8. 산출물

| 산출물 | 경로 |
|---|---|
| VDI 설정 (τ/Platt/TPR/FPR) | `apps/ai/training/configs/vdi.yaml` |
| 동결 홀드아웃 | `apps/ai/training/data/frozen_colonies.json` |
| Stage-1 golden | `apps/ai/training/eval_history/v0.2.0-stage1.json` |
| Stage-2 학습·보정 | `apps/ai/training/eval_history/v0.2.0-stage2.json` |
| Stage-2 평가 | `apps/ai/training/eval_history/v0.2.0-stage2-{golden,test,holdout}.json` |
| Gate 0 / e2e | `apps/ai/training/eval_history/v0.2.0-gate0.json`, `v0.2.0-e2e.json` |
| shakedown | `apps/ai/training/eval_history/shakedown-*.json` |
| 가중치 (박스, git 미커밋) | `training/runs/yolo/v0.2.0-stage1v2-allall/weights/best.pt`, `training/runs/stage2/v0.2.0-stage2v2-degnone/best.pt` |

---

## 9. 최종 갱신 (2026-09-26) — E3 확정, τ 정책 정정, 베이스라인

§1~§6은 v2 실패 시점의 기록이다. 이후 진행과 최종 수치는 이 절이 우선한다. 근거: 원장(`progress.md`) "E3 (cal_a sel" / "FINAL v0.2.0" / "τ-policy" / "fpr_cap sweep" / "DECISION (controller, 2026-09-25 22:35)" 줄, `eval_history/v0.2.0-*.json`, `configs/vdi.yaml`.

### 9.1 v3 실험 결과 (τ = cal-A FPR 1% 기준)

| 실험 | 변경 | cal-A / cal-B AUROC | golden AUROC | cal-B TPR / FPR | golden recall@τ |
|---|---|---|---|---|---|
| v2 | 기준(ShuffleNet, 224, val 선택) | 0.806 / 0.831 | 0.856 | 0.272 / 0.004 | 0.18 |
| E1 | 모델 선택을 cal-A AUROC로 | 0.807 / 0.848 | 0.874 | 0.046 / 0.001 | 0.06 |
| E2 | E1 + 크롭 320 px | 0.824 / 0.812 | 0.849 | 0.269 / 0.001 | 0.16 |
| **E3** | **E2 + ResNet-18** | **0.872 / 0.833** | 0.839 | **0.520 / 0.0025** | 0.40 |

결론: 백본 용량이 병목(ShuffleNet 3변형 모두 TPR ≤ 0.27). E3 = v0.2.0 최종 Stage-2 (`training/runs/stage2/v0.2.0-stage2v3-E3`, best epoch 8, early stop 18).

### 9.2 τ 정책 (스펙 v2.2, 사용자 승인 후 컨트롤러 정정)

같은 τ에서 cal-B FPR이 cal-A FPR의 1/3~1/10(colony 편차) → "cal-A FPR 1%" 규칙은 보수적. 그러나 Youden(FPR ≤ 10%)으로 재보정하자 벌 단위(cal-B TPR 0.65, golden recall 0.52)는 좋아지고 **벌통 단위 e2e는 악화**(tier 일치 0.83→0.55, 건강 프레임<3% 1.00→0.10, VDI MAE 1.9→4.2): cal-B FPR 1.85%가 golden colony의 실제 FPR 5.5%를 과소추정해 보정에서 덜 빼므로 건강 벌통이 5~6%(elevated)로 읽힘.

golden e2e 스윕(tier 일치 / 건강<3% / MAE): cap 0.01 → 0.83 / 1.00 / 1.9 · 0.02 → 0.785 / 0.775 / 2.0 · 0.05 → 0.74 / 0.63 / 2.3 · 0.10 → 0.55 / 0.10 / 4.2. cal-B e2e는 보정 원천이라 무정보(0.91~0.95).

**결정 (2026-09-25 22:35)**: `tau_policy: youden`, **`fpr_cap: 0.01`**. 원칙: tier 경계가 3%이므로 운영점은 미학습 colony에서도 FPR ≪ 3%여야 하고, TPR 부족은 보정으로 안전하나 FPR 과소추정은 안전하지 않다. cap 선택에 golden e2e를 1회 사용 → golden e2e 수치는 약간 낙관적.

최종 `vdi.yaml`: τ 0.639, TPR 0.516, FPR 0.0025 (Δ0.514 ≥ 0.5, `corrected: true`), Platt a 0.715 / b −0.710, `cal_a_fpr_at_tau` 0.0096.

### 9.3 최종 게이트 표 (E3, cap 1%)

| 게이트 (스펙 §7) | 기준 | 측정 | 판정 |
|---|---|---|---|
| Stage-1 golden | mAP50 ≥ 0.85, recall ≥ 0.90 | 0.986 / 0.961 | PASS |
| Stage-2 보정 조건 | cal-B TPR − FPR ≥ 0.5 | 0.514 | PASS |
| Stage-2 특이도 | ≥ 0.985 @τ | golden 0.994 | PASS |
| Stage-2 벌 단위 recall | ≥ 0.90 @τ | golden 0.40 | **미달** → v0.3 목표 (스펙 v2.2 §7 주) |
| 크기 베이스라인 AUROC | 진단(보고만, v2.2) | golden 0.79 / EV2 0.85 | 라벨 속성 — 게이트 아님 |
| Gate 0 px/mm | 22 대비 −15%p 붕괴점 | 0.345 / 0.336 / 0.318 / 0.282 @22/15/12/9 | 붕괴 없음 (`capture_floor` null) |
| e2e tier 일치율 | > 사소 베이스라인 | 0.83 vs 0.40 | PASS |
| 건강 프레임 < 3% | | 1.00 | PASS |
| VDI MAE (참고) | | 1.91 (target별 0.85/0.88/1.39/2.02/4.41) | |
| 단일 스테이지 베이스라인 | 2-stage가 이겨야 함 | golden 실프레임 150장: tier 일치 0.633, 건강<3% 0.963 (2-stage 0.83 / 1.00, 합성 프레임 — 동일 셋 아님) | PASS (지표상) |
| 외부 셋 | 참고 | VarroaDataset test recall@τ 0.825 (AUROC 0.952), EV2 holdout recall 0.389 (AUROC 0.955) | |

### 9.4 산출물

- 박스: `training/runs/stage2/v0.2.0-stage2v3-E3/{best.pt, stage2.onnx, metadata.json, vdi.yaml}` (ResNet-18, 입력 320, featmap 512×10×10, `fc_weight` 512), `training/runs/yolo/v0.2.0-stage1v2-allall/weights/{best.pt, best.onnx}` (imgsz 1024, opset 17), 크롭 `training/crops-320`, 베이스라인 `training/runs/yolo/v0.2.0-baseline-single`.
- S3: `s3://helpbee-models/two-stage/v0.2.0/{stage1.onnx, stage2.onnx, metadata.json, vdi.yaml}` (2026-09-25 23:00).
- 커밋: `apps/ai/training/configs/vdi.yaml`, `eval_history/v0.2.0-{stage1,stage2,stage2-golden,stage2-test,stage2-holdout,gate0,e2e}.json`, 스펙 v2.2(ccc6723, 352765f).
- 다음: 계획 2(서빙·스키마·앱) — Task 1(API/DB 관용화) 완료(c05626d, fb8da06), Task 2(AI 서빙) 진행.
