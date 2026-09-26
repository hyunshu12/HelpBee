# ADR-0002 — 2-stage 벌 단위 감염 분류 + VDI 지표 (v0.2.0)

> Status: **ACCEPTED** (2026-09-25 사용자 승인, 스펙 v2.2)
> Decision owner: AI팀 lead (프로젝트 소유자)
> **Supersedes: ADR-0001** (`ADR-0001-yolo-engine-architecture.md` — 단일 스테이지 v0.1.0 → 2-stage 단계적 계획)
> 단일 기준 문서: [`docs/superpowers/specs/2026-09-22-ai-two-stage-redesign-design.md`](../../superpowers/specs/2026-09-22-ai-two-stage-redesign-design.md) (v2.2) — 이 ADR과 스펙이 다르면 **스펙이 우선**한다.
> 검증 기록: [`2026-09-25-v020-two-stage-training.md`](../../05-implementation/2026-09-25-v020-two-stage-training.md) (계획 1, 학습·게이트) · [`2026-09-26-two-stage-v020-serving.md`](../../05-implementation/2026-09-26-two-stage-v020-serving.md) (계획 2, 서빙·스키마·앱) · `apps/ai/training/eval_history/v0.2.0-{stage1,stage2,stage2-golden,stage2-test,stage2-holdout,gate0,e2e}.json`

---

## 1. 결정 (Decision)

자체 AI 진단 엔진을 **2-stage 벌 단위 감염 분류 + VDI(가시 감염 지수)** 로 교체한다. v0.1.0 단일 스테이지 3-class 검출은 퇴역(롤백 경로 `AI_ENGINE=yolo-v1`로만 보존)한다.

| 구성 | 결정 (스펙 v2.2) |
|---|---|
| Stage-1 | **YOLO11s 1-class `bee`(성충)**, 입력 1024, ≥8MP면 2×2 타일(IoMin NMS), conf 0.15, max_det 1500 |
| 크롭 | Stage-1 **예측 박스**를 원본 좌표로 → 원본 해상도 크롭(여백 10%) → 종횡비 유지 패딩 → **320 px** |
| Stage-2 | **ResNet-18 벌 단위 감염 분류기**, 64개 청크, Platt 보정 p, `infested = p > τ` |
| τ 정책 | cal-A에서 **Youden 최대점(TPR − FPR), 단 cal-A FPR ≤ 1%** (`tau_policy: youden`, `fpr_cap: 0.01`). 최종 τ 0.639 |
| 지표 | **VDI** = Rogan–Gladen 보정 `clip((raw − FPR)/(TPR − FPR), 0, 100)`, raw = k/n×100. TPR/FPR은 cal-B 측정값(0.516 / 0.0025, Δ0.514 ≥ 0.5 → `corrected: true`). Δ < 0.5면 `vdi = raw`, `corrected: false` |
| 신뢰구간 | raw k/n의 **Jeffreys** 이항 구간 → Rogan–Gladen 사상(하한 0 floor). "표본 신뢰구간(분류기 오차 미포함)" |
| tier | `vdi_display`(AI가 한 번만 반올림)에서만 계산, 반열림: `low` [0,3) · `elevated` [3,10) · `high` [10,∞) · `insufficient` = 벌 0마리 또는 `quality.ok == false` |
| 전제 | **비영리 포트폴리오** (스펙 A1): AI Hub 71667 영리 금지 조항 비적용, 유료 티어는 `PORTFOLIO_MODE`로 비활성. 상용 전환 시 NIA 사전 승낙 재검토 |

---

## 2. 맥락 (Context)

ADR-0001(2026-06-05)은 단일 스테이지 v0.1.0을 먼저 내고 2-stage를 라이선스 게이트 뒤로 미뤘다. 이후 드러난 사실이 전제를 바꿨다.

- **v0.1.0 결함**: 71667 bbox를 COCO xywh로 오독(실제 xyxy — 박스가 중앙값 12배 부풂), 학습 레시피 유실, tier 경계 불일치, 게이트 공백. "감염률 3%/10%"는 워시 수치를 이미지 지표에 붙인 범주 오류.
- **라이선스 게이트 해소**: 프로젝트가 비영리 포트폴리오로 확정(2026-09-22)되어 ADR-0001 §8 Q1의 상용 제약이 적용되지 않음.
- **목표 재정의**: 실제 벌 개체별 감염 판정을 보여주는 시연. 거짓 양성으로 무너지지 않도록 보정·게이트 포함.

---

## 3. 근거 (Rationale)

1. **왜 2-stage인가** (스펙 §0): (a) 외부 감염 라벨 데이터(VarroaDataset·EV2)는 **벌 크롭**이라 분류기만 학습 가능, (b) 크롭을 원본에서 떠서 Stage-2 해상도 손실이 없음, (c) Bilik 2021에서 벌 단위 판정이 응애 개체 탐지보다 F1 +16%p.
2. **단일 스테이지를 이겼다** (스펙 §7 e2e 베이스라인 요구): xyxy 정정 + 성충 2-class 단일 YOLO 베이스라인은 golden 실프레임 150장에서 **tier 일치 0.633** (건강<3% 0.963), 2-stage는 **0.83** (건강<3% 1.00). 단, 2-stage 수치는 합성 프레임 기반이라 동일 셋 비교는 아니다 — 지표상 PASS.
3. **백본 = ResNet-18** (v2.2): ShuffleNet-V2 x1.0 @224는 3개 변형 모두 cal-B TPR ≤ 0.27로 보정 조건(TPR − FPR ≥ 0.5) 실패. E3(ResNet-18, 320 px, cal-A AUROC 모델 선택)만 cal-B TPR 0.520 / FPR 0.0025로 통과 — 병목은 백본 용량.
4. **τ = Youden + FPR 1% 상한**: Youden은 스펙의 보정 조건과 같은 양. 상한은 tier 경계(3%) 때문에 필요 — 미학습 colony에서도 FPR ≪ 3%여야 하며, TPR 부족은 보정으로 안전하지만 FPR 과소추정은 건강 벌통을 `elevated`로 읽게 만든다.

### 최종 게이트 (계획 1 기록 §9.3)

| 게이트 | 측정 | 판정 |
|---|---|---|
| Stage-1 golden mAP50 / recall | 0.986 / 0.961 | PASS |
| Stage-2 보정 조건 (cal-B TPR − FPR ≥ 0.5) | 0.514 | PASS |
| Stage-2 특이도 @τ | golden 0.994 | PASS |
| Stage-2 벌 단위 recall @τ ≥ 0.90 | golden 0.40 | 미달 → v0.3 목표 |
| e2e tier 일치 / 건강<3% / VDI MAE | 0.83 / 1.00 / 1.91 | PASS |

---

## 4. 기각한 대안 (Rejected)

- **ShuffleNet-V2 x1.0 @224** (스펙 v2.1 원안): 3개 변형 모두 게이트 실패. CPU 예산이 더 빡빡할 때의 **문서화된 폴백**으로만 유지.
- **FPR 상한 ≥ 2%**: golden e2e 스윕에서 cap 0.02 → tier 일치 0.785 / 건강<3% 0.775, 0.05 → 0.74 / 0.63, 0.10 → 0.55 / 0.10 / MAE 4.2. 벌 단위 지표(cap 0.10: cal-B TPR 0.65)는 좋아지지만 cal-B FPR이 미학습 colony FPR을 과소추정해 건강 벌통이 5~6%(`elevated`)로 읽힘. cap 선택에 golden e2e를 1회 썼으므로 golden e2e 수치는 약간 낙관적.
- **단일 스테이지 유지** (ADR-0001 v0.1.0): 위 §3-2 베이스라인에 짐.
- **크기 베이스라인 AUROC 게이트**: 라벨(GT 박스 크기)의 성질이라 게이트에서 진단(보고만)으로 강등.

---

## 5. 결과 (Consequences)

- **서빙 비용**: ResNet-18 CPU ≈ **15 ms/크롭 @320**, 요청당 ≈450 GFLOP. 시연 인스턴스는 T3 Unlimited 또는 c6i.large 권고. 실번들 스모크: 18마리 0.94 s, 9MP 타일 1.7 s.
- **타임아웃 체인**: 모바일 `receiveTimeout` ≥ 95 s ≥ ai-client two-stage 경로 90 s(`AI_TIMEOUT_MS_TWO_STAGE`) ≥ AI 내부 예산.
- **이중 출력 기간** (스펙 §8 B7): AI는 새 필드와 함께 `risk_score := score_mapping(vdi)`(0~100 점수, `round(vdi)` 아님) + `tier_legacy`를 한 릴리스 동안 같이 낸다. 구 필드 제거(계획 2 Task 8)는 develop 머지 + 1회 배포 후.
- **`risk.py` 동결**: `risk.py`/`risk.yaml`은 OpenAI 폴백·부스 앱 전용 shim. OpenAI 결과는 rate → `vdi_raw`, `corrected:false`, `bee_total/bee_infested/sampling_ci95 = null`로 새 계약을 채운다. 부스 JSON 동결.
- **스키마**: `analyses`에 nullable `vdi, vdi_ci_low, vdi_ci_high, bee_total, bee_infested`; `ai_models`에 `('yolo','helpbee-two-stage','0.2.0')`. 트렌드는 two-stage=`vdi`, 구 row=`varroa_infection_risk`로 분리(단위 상이, coalesce 금지). N장 합산은 읽기 시 원시 카운트 Σk/Σn으로 재계산.
- **수용한 리스크** (소유자): FHD 프레임은 벌 5~19마리라 감염 1마리면 `high` — 배지·CI로만 완화, tier는 점추정 기준.
- **품질 임계 미보정**: 블러(Laplacian < 100)·노출([40,215]) 초기값이 Sample FHD 성충의 47%를 실패시킴 → 실제 폰 사진(Gate 0(a)) 확보 후 `vdi.yaml` `quality`에서 보정.
- **가중치**: `s3://helpbee-models/two-stage/v0.2.0/{stage1.onnx, stage2.onnx, vdi.yaml, metadata.json}`, 로더 env `TWO_STAGE_MODEL_VERSION`.
- **v0.1.0 기준점**: 로컬 태그 `v0.1.0-single-stage` (two-stage 분기 직전 develop 커밋, push 여부는 소유자 결정).

---

## 6. 링크

- 스펙 v2.2 (단일 기준): `docs/superpowers/specs/2026-09-22-ai-two-stage-redesign-design.md`
- 적대적 검증: `docs/superpowers/specs/2026-09-23-ai-two-stage-redesign-adversarial-review.md`
- 계획 1 기록: `docs/05-implementation/2026-09-25-v020-two-stage-training.md`
- 계획 2 기록: `docs/05-implementation/2026-09-26-two-stage-v020-serving.md`
- 평가 산출물: `apps/ai/training/eval_history/v0.2.0-*.json`, `apps/ai/training/configs/vdi.yaml`
- 대체된 결정: `ADR-0001-yolo-engine-architecture.md`
