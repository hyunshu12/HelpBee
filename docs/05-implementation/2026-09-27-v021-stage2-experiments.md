# 2026-09-27 — AI v0.2.1 Stage-2 실험 기록 (백본·학습 프로토콜·교차 보정 진단 → E3 유지)

> PR: (미생성) · 브랜치: `feature/ai-two-stage-redesign-spec` · 커밋 `735f114`…`03680de` (+ 이 문서 커밋)
>
> 근거: 실행별 지표 [`apps/ai/training/eval_history/v0.2.1-experiments.json`](../../apps/ai/training/eval_history/v0.2.1-experiments.json)(이 문서와 같은 커밋),
> SDD 원장 `.superpowers/sdd/2026-09-23-ai-two-stage-plan1-data-training/progress.md` 191–230행(controller 판정·진단·라운드별 결과).
> 선행 기록: [2026-09-25 v0.2.0 Training](./2026-09-25-v020-two-stage-training.md) · [2026-09-26 v0.2.0 서빙](./2026-09-26-two-stage-v020-serving.md).
> **분석 전용 실험이다. 출하 모델은 v0.2.0 E3(ResNet-18 @320) 그대로이며 S3 번들·`vdi.yaml`·회귀 매니페스트는 바꾸지 않았다.**

---

## 1. 요약

- 목표: Stage-2(크롭 응애 가시 분류기)를 백본 확장과 학습 프로토콜 개선으로 E3보다 낫게 만드는 것. 결과가 교체 규칙(§2)을 넘으면 v0.2.1로 출하하려 했다.
- 3라운드, 11개 모델(E3c 1 · 30 epoch annealed `last` 6 · `cal_a_tpr1` 선택 4, 크래시·중단 제외)을 학습·보정·평가했다. **교체 규칙을 통과한 후보는 없다. E3가 계속 출하 모델이다.**
- 순위 지표는 대부분 좋아졌다(golden AUROC 0.839 → 0.88–0.90, VarroaDataset test 0.95 → 0.97–0.98, EV2 holdout 0.955 → 0.98–0.99). 반면 **실제로 쓰는 동작점(τ, FPR ≈ 1% 이하)** 에서는 E3가 가장 좋았다. crossfit 평균 Δ 0.540, colony 002 내부 oracle TPR@FPR1% 0.506, e2e tier 일치 0.83 / 건강 프레임 1.00.
- 병목은 모델 용량이 아니다. **보정셋의 colony 다양성**이다. cal-A는 사실상 colony 002, cal-B는 사실상 colony 010이고, 같은 τ에서 음성 FPR이 colony마다 약 10배까지 달라진다. 이 편차를 단일 FPR로 가정하는 Rogan–Gladen 보정이 흡수하지 못해서 건강한 프레임에서 오경보가 난다.
- 부수 발견: v0.2.0은 `workers=0`으로 학습됐다. 그래서 **샘플마다 매 epoch 같은 증강을 받았다**(잠재 약점, §3).

## 2. 목표와 교체 규칙

후보 순위는 선택 분할(cal-A)로만 매겼다. cal-B TPR/FPR과 golden e2e는 **보고와 비회귀 확인 용도이지 선택 기준이 아니다**(ruling, 원장 194행).

| 시점 | 교체 조건 (모두 충족) |
|---|---|
| 라운드 1 (v4 ruling) | cal-A AUROC ≥ E3 + 0.01 **이고** 그 향상폭 > 재현 간 편차 \|E3c − E3\| · cal-B AUROC ≥ E3(0.833) · cal-B TPR−FPR(Δ) ≥ 0.5(→ `corrected:true`) · golden e2e tier 일치 ≥ 0.83 **그리고** 건강 프레임 VDI<3% = 1.00 · CPU ≤ 40 ms/crop(1,500 크롭 ≤ 60 s, 90 s 예산 안) |
| 라운드 3 (v8 ruling) | cal-B Δ ≥ 0.5 · crossfit 평균 Δ > 0.540(E3) · colony 002 oracle TPR@FPR1% > 0.506(E3) · e2e ≥ 0.83 / 건강 1.00 · CPU ≤ 40 ms/crop |

후보가 통과하면 v0.2.1 번들을 만들고 회귀 매니페스트를 재생성할 예정이었다(가중치 변경 규칙, `apps/ai/CLAUDE.md` §10-2). 통과한 후보가 없어서 둘 다 하지 않았다.

> CPU 40 ms 기준은 Mac CPU 벤치(@320, b64, 4 threads: r18 18 · r34 36 · r50 42 · effb0 11 ms/crop)를 보고 정했다. 학습 박스 2 threads p50으로 재면 E3도 41 ms이다(§6). 따라서 절대값보다 **E3 대비 배수**로 판단한다.

## 3. 코드 산출물 (커밋 735f114…03680de)

모두 `apps/ai/training/train_stage2.py` · `training/configs/stage2.yaml` · `app/tests/unit/test_train_stage2.py`를 고쳤고, 기본값은 v0.2.0 재현 경로(`amp: false`, `swa_epochs: 0`, `select_metric: cal_a_auroc`)를 유지한다.

| 커밋 | 내용 |
|---|---|
| `735f114` | 백본 확장 `resnet34`/`resnet50`/`efficientnet_b0`(featmap C = 512/2048/1280, `fc Linear(C,1)`, metadata `feat_channels`). `CropDataset`을 **모듈 최상위의 피클 가능한 클래스**로 바꿔 Windows spawn에서도 DataLoader 워커가 동작한다(`workers: 4`, `seed_worker`+generator). **epoch 7.5분 → 2.1분**. `training/bench_stage2.py`(onnxruntime CPU ms/crop 벤치, `test_bench_stage2.py`) 추가, `tasks.py` 연결 |
| `f78d2da`, `d365f1e` | opt-in AMP(`amp`, fp16 autocast forward + GradScaler, fp32 master 가중치). 최종 Platt/τ/cal-B 보정은 **항상 fp32**로 서빙 ONNX와 맞췄다. GradScaler 폴백, amp 조기 검사, CPU on/off 비트 동일 테스트 포함 |
| `9c79b0b`, `fa33db3` | `select_metric: last`(조기 종료 없이 마지막 epoch) + `swa_epochs`(마지막 k epoch 가중치 평균 + BN 재계산). BN 재계산 중에는 BN만 train 모드로 둔다(EfficientNet StochasticDepth/Dropout은 eval, momentum 복원) |
| `9a0adba` | **학습 후 메모리 해제**: 보정 전에 optimizer/scheduler/GradScaler/학습 로더/샘플러를 del하고 `zero_grad` + `gc` + `empty_cache`(MiB 로그 기록). 학습 후 로더는 `pin_memory=False`, `eval_batch` 설정 추가. → AMP 학습 뒤 fp32 보정 단계의 OOM 해결(§4.1 E4) |
| `713f4be` | SWA BN 재추정을 **학습 분포**(증강 + 같은 가중 샘플러, `swa_bn_loader`)로 한다(§4.2 진단) |
| `9705977` | `--finalize <run_dir> --ckpt last.pt --out <dir>`: 체크포인트 하나를 보정·ONNX export·평가 산출물로 만든다. 공유 `_calibrate_export`를 쓰고 **`<out_dir>`에만 쓴다**(출하 `vdi.yaml`/`eval_history` 미기록, 비어 있지 않은 out이면 `FileExistsError`). 학습 후 크래시는 재학습 대신 재보정으로 복구한다 |
| `03680de` | `select_metric: cal_a_tpr1` = cal-A 음성 FPR 1% 지점의 cal-A TPR(logit 기준이라 Platt와 무관하고, 정수 분위수·strict `>`·FPR ≤ 목표). 리포트에 `tpr_at_fpr1 {cal_a, cal_b}` 추가, SWA 리포트 KeyError 수정 |

테스트: `735f114` 시점 262 passed / 30 skipped, `9705977` 시점 273 passed / 43 skipped(Mac). 박스에서는 체인 시작 전에 `test_train_stage2.py` 전체를 돌렸다.

**잠재 발견 (v0.2.0):** `workers=0`에서는 샘플별 증강 RNG 시드가 `[seed, i, initial_seed, 0]`로 epoch마다 같다. 즉 **E3는 샘플마다 매 epoch 같은 증강으로 학습됐다**. `workers>0`이면 epoch마다 새 증강이 나온다. E3c(아래)를 대조군으로 둔 이유 중 하나는 증강 다양성 효과와 백본 효과를 분리하기 위해서다.

## 4. 라운드별 결과

공통: 크롭 320 px(crops v2), τ 정책 = cal-A Youden(FPR 상한 0.01), 평가 = golden / VarroaDataset test / EV2 holdout + e2e(golden 의사 프레임). 표의 Δ = cal-B TPR − FPR. e2e = tier 일치 / 건강 프레임 VDI<3% 비율 / VDI MAE. CPU = 박스 2 threads p50 ms/crop.

### 4.1 라운드 1 — 대조군 E3c, 백본 E4–E6 (select `cal_a_auroc`)

| 실행 | 설정 | best ep / 실행 ep | cal-A / cal-B AUROC | golden AUROC | τ | cal-B TPR / FPR (Δ) | e2e | CPU |
|---|---|---|---|---|---|---|---|---|
| **E3 (출하)** | r18, fp32, workers 0 | 8 / — | 0.872 / 0.833 | 0.839 | 0.639 | 0.516 / 0.0025 (**0.514**, corrected) | **0.83 / 1.00 / 1.91** | 41.3 |
| E3c | r18, amp, workers 4 (나머지 동일) | **0** / 11 | 0.884 / 0.868 | 0.890 | 0.539 | 0.384 / 0.0003 (0.384, 미보정) | 0.50 / 1.00 / 4.33 | 44.5 |
| E4 | r34, amp, b64 → b48 | (시도1) 28 / 39 | cal-A 0.905(ep 28, 관측 최고) | — | — | — | — | — |
| E5 | r50 | — | — | — | — | — | — | — |

- **E3c**: 로더/AMP 경로는 정상이고 epoch은 2.1분이었다. 그런데 epoch별 cal-A AUROC가 0.88/0.77/0.88/0.79/0.87…로 요동쳐 best epoch이 0으로 잡혔다. 순위 지표는 전부 E3보다 높았지만 Δ < 0.5여서 보정이 꺼졌고, e2e가 0.50으로 떨어졌다.
- **E4 OOM**: 학습 중 OOM이 **아니었다**. 시도 1(39 epoch, 조기 종료 @38)과 시도 2(b48, 14 epoch) 모두 학습이 끝난 뒤 첫 fp32 `_predict_logits(cal_a)`에서 `CUDA error: out of memory`로 죽었다(pin-memory 스레드에서 표면화). optimizer, GradScaler, 학습 로더, AMP 크기의 캐시 블록이 남은 상태에서 fp32 activation(fp16의 2배)을 잡으려다 실패한 것이다 → `9a0adba`로 수정. 재시도가 같은 run 디렉터리를 재사용하는 바람에 **epoch 28 가중치(관측 최고 cal-A 0.905)를 덮어써 잃었다.**
- **E5**(r50)는 같은 결말이 예상돼 controller가 중단했다. **E6**(effb0)과 라운드 2a 체인은 시작 전에 취소했다.

**진단 (원장 206행):** (1) cosine `T_max=50`인데 patience 10으로 ep 10–18에서 멈춘다. 그 시점 LR은 아직 최대의 약 0.9배이므로, 선택된 체크포인트는 **전부 고LR 반복점**이다(출하 E3 ep 8 포함). (2) cal-A 양성 1009개 중 1002개가 colony 002, cal-B 양성 562개 중 555개가 colony 010이다. **사실상 단일 colony 셋**이고 표본 SE가 약 0.006이라, 0.77↔0.88 요동은 잡음이 아니라 실제 colony 간 불안정이다. 이런 곡선에서 epoch 최대값으로 고르면 운 좋은 반복점을 고르게 된다. 재현 간 편차 \|E3c − E3\|는 cal-A AUROC 0.012, cal-B AUROC 0.035다.

### 4.2 라운드 2 — 30 epoch annealed `last` (cosine→0, 조기 종료 없음), 3 백본 × 2 seed

프로토콜: epochs 30, `select_metric: last` + `swa_epochs: 10`. SWA는 진단(아래) 뒤 실험에서 뺐고, 각 run의 `last.pt`를 `--finalize`로 보정·평가했다. r50은 8 GB 한계와 CPU 42 ms(Mac)로 경계선이라 제외했다.

| 실행 | cal-A / cal-B AUROC | golden AUROC | test / EV2 AUROC | τ | cal-B TPR / FPR (Δ) | e2e | CPU |
|---|---|---|---|---|---|---|---|
| **E3 (출하)** | 0.872 / 0.833 | 0.839 | 0.952 / 0.955 | 0.639 | 0.516 / 0.0025 (**0.514**) | **0.83 / 1.00 / 1.91** | 41.3 |
| r34-s42 | 0.889 / 0.855 | 0.882 | 0.975 / 0.982 | 0.475 | 0.294 / 0.0003 (0.293) | 0.40 / 1.00 / 6.52 | 73.5 |
| r34-s7 | 0.885 / 0.877 | 0.902 | 0.967 / 0.987 | 0.499 | 0.370 / 0.0015 (0.369) | 0.46 / 0.875 / 4.36 | 74.7 |
| r18-s42 | 0.826 / 0.844 | 0.879 | 0.975 / 0.988 | 0.460 | 0.100 / 0.0002 (0.099) | 0.40 / 1.00 / 7.01 | 45.2 |
| r18-s7 | 0.793 / 0.846 | 0.887 | 0.967 / 0.990 | 0.405 | 0.224 / 0.0001 (0.224) | 0.40 / 1.00 / 7.05 | 39.1 |
| effb0-s42 | 0.817 / 0.843 | 0.840 | 0.951 / 0.922 | 0.611 | 0.000 / 0.0001 (0.000) | 0.40 / 1.00 / 7.80 | 26.8 |
| effb0-s7 | 0.858 / 0.801 | 0.865 | 0.961 / 0.991 | 0.600 | 0.000 / 0.0000 (0.000) | 0.40 / 1.00 / 7.80 | 27.1 |

- 고정 스케줄은 안정적이었다. r34-s42의 epoch별 cal-A는 ep 21–29에서 0.87–0.90이다(구 0.77↔0.88 요동 해소). E4 시도 1에서도 LR이 줄수록 cal-A가 올라서(ep 28 0.905) 12 epoch 스케줄은 짧다고 봤다.
- 전 모델이 게이트에서 **탈락했다**(Δ 0.00–0.37, e2e 0.40–0.46; 0.40은 "전부 low" 사소 기준선과 같다). effb0은 τ ≈ 0.60에서 모든 셋의 recall이 0이다(Platt/τ 이전 완전 실패). r34-s7은 건강 프레임 1장에서 오경보가 났다(0.875). seed 간 편차가 크다(r18 cal-A 0.826 vs 0.793, effb0 0.817 vs 0.858).

**SWA 붕괴 진단 (`diag_swa.py`, r34-s42, cal-A 부분표본 양성 1009 + 음성 2000, CPU fp32):** SWA 모델이 val 0.943 / cal-A **0.532**로 망가졌다(τ 0.189, cal-B TPR 0.005, e2e 0.40).

| 변형 | cal-A AUROC |
|---|---|
| `last` (평균 없음) | 0.886 |
| SWA + BN을 비증강·비가중 train 행으로 재계산 | **0.528** |
| SWA + 마지막 epoch BN 통계 유지 | 0.870 |
| SWA + BN을 학습 분포(증강 + 가중 샘플러)로 재계산 | 0.885 |

→ BN 재계산은 **학습 분포**로 해야 한다(`713f4be`). 그렇게 해도 SWA는 `last`와 거의 같다(평균 구간 LR ≈ 0). 모델이 BN 통계에 매우 민감하다는 점도 드러났다. 서빙은 고정 running stats를 쓰므로 서빙 영향은 없다. **결론: 프로토콜 = annealed 마지막 epoch, SWA는 실험에서 제외.**

### 4.3 교차 보정 진단 (`crossfit.py`, 분석 전용)

τ를 한 보정셋에서 Youden-1%로 적합한 뒤 다른 셋에서 측정했다. A→B = 현 프로토콜(cal-A 적합 → cal-B 측정). oracle = colony 내부에서 FPR 1%일 때의 TPR(τ 이전을 제외한 상한).

| 모델 | A→B Δ | B→A FPR on A | B→A Δ | 평균 Δ | oracle 002 | oracle 010 |
|---|---|---|---|---|---|---|
| v2 (degnone) | 0.279 | 3.3% | 0.365 | 0.322 | 0.234 | 0.375 |
| E1 (shufflenet @224) | 0.046 | 9.8% | 0.445 | 0.245 | 0.101 | 0.438 |
| E2 (shufflenet @320) | 0.270 | 8.9% | 0.531 | 0.400 | 0.250 | 0.532 |
| **E3 (출하)** | **0.514** | 5.2% | 0.566 | **0.540** | **0.506** | 0.609 |
| E3c | 0.384 | 20.4% | 0.596 | 0.490 | 0.491 | 0.537 |
| r34-s42-last | 0.293 | 25.4% | 0.602 | 0.448 | 0.144 | 0.598 |
| r34-s7-last | 0.369 | 19.4% | 0.611 | 0.490 | 0.313 | 0.641 |
| r18-s42-last | 0.099 | 24.5% | 0.514 | 0.307 | 0.066 | 0.622 |
| r18-s7-last | 0.224 | 24.8% | 0.464 | 0.344 | 0.070 | 0.586 |
| effb0-s42-last | 0.000 | 20.4% | 0.550 | 0.275 | 0.001 | 0.559 |
| effb0-s7-last | 0.000 | 7.4% | 0.464 | 0.232 | 0.003 | 0.429 |

- **colony 010에서 적합한 τ를 colony 002에 대면 FPR이 3–25%다.** 반대 방향(002에서 적합 → 010에서 측정)은 FPR ≤ 0.25%다. colony 002 음성은 "어려운" 음성이다. 따라서 A에서 τ를 잡는 현 프로토콜이 안전한 방향이다.
- **동작 영역에서는 E3가 최선이다**(평균 Δ 0.540, oracle 002 0.506). 운만 좋았던 게 아니다. 새 모델의 AUROC 향상은 더 높은 FPR 구간에 몰려 있다. **전체 AUROC로 고르는 것 ≠ 동작점 성능.** → 라운드 3의 선택 지표를 `cal_a_tpr1`로 바꿨다.

### 4.4 라운드 3 — `cal_a_tpr1` 선택 (30 epoch cosine, 조기 종료 없음), r18·r34 × s42·s7

| 실행 | best ep | TPR@FPR1% cal-A / cal-B | cal-A / cal-B AUROC | golden AUROC / spec | τ | cal-B TPR / FPR (Δ) | 평균 Δ / orc002 | e2e | CPU |
|---|---|---|---|---|---|---|---|---|---|
| **E3 (출하)** | 8 | — | 0.872 / 0.833 | 0.839 / 0.994 | 0.639 | 0.516 / 0.0025 (0.514 ✓) | 0.540 / 0.506 | **0.83 / 1.00 / 1.91** | 41.3 |
| r34-s42 | 14 | 0.566 / 0.651 | 0.883 / 0.873 | 0.885 / 0.982 | 0.510 | 0.541 / 0.0003 (0.541 ✓) | 0.535 / **0.557** | 0.67 / **0.45** / 2.67 | 80.3 |
| r34-s7 | 8 | 0.580 / 0.612 | 0.888 / 0.873 | 0.899 / 0.994 | 0.560 | 0.489 / 0.0006 (0.489 ✗) | **0.558** / **0.575** | 0.48 / 1.00 / 4.24 | 88.1 |
| r18-s42 | 1 | 0.489 / 0.587 | 0.833 / 0.879 | 0.891 / 0.987 | 0.492 | 0.512 / 0.0014 (0.511 ✓) | 0.533 / 0.482 | 0.735 / 0.75 / 2.03 | 44.7 |
| r18-s7 | 8 | 0.486 / 0.614 | 0.873 / 0.872 | 0.898 / 0.986 | 0.523 | 0.546 / 0.0015 (0.545 ✓) | **0.573** / 0.475 | 0.76 / 0.575 / 2.13 | 41.5 |

- cal-B 게이트는 3/4이 통과했고, crossfit 평균 Δ·oracle 002에서 E3를 넘는 후보도 나왔다. golden recall은 0.38–0.43(E3 0.40)이다. EV2 holdout recall은 r18에서 크게 올랐다(0.76 / 0.69, E3 0.39).
- 그러나 **golden 특이도가 0.982–0.994로 E3(0.994)보다 낮거나 같다.** 그래서 건강 프레임 VDI<3% 비율이 0.45 / 1.00 / 0.75 / 0.575로 떨어졌다. e2e tier 일치도 0.48–0.76으로 모두 E3의 0.83에 못 미친다. r34-s7만 건강 1.00을 지켰는데, Δ 0.489 < 0.5라 미보정 상태이고 tier 일치가 0.48이다. **교체 규칙 통과 0건.**

## 5. 진단 — 왜 순위 향상이 동작점 향상으로 안 이어지는가

1. **보정셋이 사실상 단일 colony다.** cal-A 양성 1009개 중 1002개가 colony 002, cal-B 양성 562개 중 555개가 colony 010이다(분할상 cal_a = 002 + 020, cal_b = 010 + 016).
2. **음성 점수 분포가 colony마다 다르다.** colony 002 음성은 점수가 높다. 010에서 τ를 잡으면 002의 FPR은 3–25%(라운드 3 포함 최대 30%)가 되고, 반대 방향은 ≤ 0.25%다.
3. **전체 AUROC 향상은 높은 FPR 구간에 있다.** FPR ≈ 1% 이하의 동작 영역에서 colony 002 oracle TPR은 E3 0.506이 라운드 2 전 모델보다 높았다. 라운드 3는 이 영역을 직접 최적화해 0.557/0.575까지 올렸다.
4. **그래도 golden colony(001/028/022)의 FPR이 cal-B보다 크게 높다.** 선택된 τ에서 golden FPR(1 − spec)과 cal-B FPR을 비교하면 라운드 3는 1.8% vs 0.03% · 0.6% vs 0.06% · 1.3% vs 0.14% · 1.4% vs 0.15%로 **약 10배 이상**이고, E3는 0.57% vs 0.25%(약 2.3배)다. Rogan–Gladen은 cal-B FPR 하나로 보정한다. 그래서 건강한 벌통에서도 raw 감염률이 FPR만큼 깔리고, 보정 후 VDI가 3% 경계를 넘는 프레임이 생긴다. 예로 r18-s42 평균치를 넣으면 (1.27 − 0.14)/0.511 ≈ 2.2%다(프레임별 표본 변동이 이를 3% 위로 밀어 올린다).
5. 결론: gate 통과 여부는 colony 002 대 010의 음성 점수 불일치가 좌우한다. 이는 라운드 2 게이트 이전 실패, crossfit(B→A FPR 3–30%), 라운드 3 golden FPR로 세 번 확인됐다. **용량을 늘리는 방향(백본)은 이 문제를 풀지 못한다.**

## 6. CPU 비용 (학습 박스, 2 threads, onnxruntime, p50 ms/crop)

| 백본 | ms/crop | E3 대비 |
|---|---|---|
| ResNet-18 (E3 / E3c / r18 계열) | 41.3 / 44.5 / 39.1–45.2 | 1.0× |
| ResNet-34 | 73.5–88.1 | ≈ 1.8–2.1× |
| EfficientNet-B0 | 26.8–27.1 | ≈ 0.65× |

ResNet-34로 바꾸면 Stage-2 서빙 시간이 **대략 2배**가 된다(1,500 크롭 기준 약 60 s → 110–130 s로, 90 s 예산 초과 위험). EfficientNet-B0는 빠르지만 τ 이전 실패로 쓸 수 없다.

## 7. 결정

- **E3(v0.2.0) 유지.** S3 `two-stage/v0.2.0` 번들, `training/configs/vdi.yaml`, `app/tests/fixtures/regression_manifest.json`은 변경 없음. GPU 실험은 종료했다.
- 새 코드 경로(백본·AMP·`last`·SWA·`--finalize`·`cal_a_tpr1`)는 opt-in이다. 기본값은 v0.2.0 재현 경로로 남겨 둔다.
- 384 px 재크롭(원래 E4–E6 결과 후 결정 예정)은 병목이 해상도가 아니라서 진행하지 않았다.

## 8. 후속 (사용자 결정 필요)

1. **보정셋 재동결**: cal-A·cal-B를 각각 **colony 3개 이상**으로 구성하고, τ는 **가장 나쁜 colony의 FPR**을 기준으로 정한다(평균 FPR 기준 아님). 스펙 §3/§7 변경 + `frozen_colonies.json`("영구 동결") 재동결이 필요하다. 그 후 E3와 라운드 3 후보를 재보정만 해서 다시 비교할 수 있다(`--finalize`는 재학습 없이 가능).
2. **현장 사진**: 실제 양봉가 사진으로 colony 간 음성 FPR 편차와 건강 벌통 오경보를 실측한다.
3. (참고) E4 시도 1의 cal-A 0.905(r34, ep 28)는 가중치를 잃어 재현하지 못했다. 1번을 하더라도 CPU 2배 비용 때문에 r34는 후순위다.

## 9. 운영 교훈

- **재시도는 항상 새 run 이름으로 한다.** 같은 디렉터리를 재사용하면 이전 시도의 best 가중치가 덮어써진다(E4 ep 28 손실). 학습 후 크래시는 재학습 말고 `--finalize`로 재보정한다.
- PowerShell `$env:X=""`는 빈 값 설정이 아니라 **변수 삭제**다(CPU 강제 override가 무시돼 finalize가 GPU에서 돌았다. OOM은 없었다).
- Windows PowerShell 5의 `>` 리다이렉트는 **UTF-16**으로 쓴다. 로그·JSON은 `Out-File -Encoding utf8` 등으로 저장한다.
- Windows는 spawn 방식이라 DataLoader 워커나 multiprocessing을 쓰는 **scratch 스크립트에 `if __name__ == "__main__":` 가드가 필요하다**(`crossfit.py` 첫 실행 크래시).

## 참조

- 권위 가이드: [`apps/ai/CLAUDE.md`](../../apps/ai/CLAUDE.md) §8(two-stage) · §10-2(회귀 게이트)
- 스펙: `docs/superpowers/specs/2026-09-22-ai-two-stage-redesign-design.md` §3·§7 · 결정: [ADR-0002](../01-development/adr/ADR-0002-two-stage-vdi-redesign.md)
- 실행 지표: `apps/ai/training/eval_history/v0.2.1-experiments.json` · 출하 기준: `eval_history/v0.2.0-*.json`
- scratch 진단 스크립트(`diag_swa.py`, `crossfit.py`)와 run 디렉터리(`training\runs\stage2\v0.2.0-stage2v{4,6,8}-*`)는 학습 박스에만 있다(미커밋).
