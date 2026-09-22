# HelpBee AI 재설계 — 2-Stage 벌 단위 감염 분류 + VDI 지표 (v0.2.0 목표)

> **Status: DRAFT → 사용자 승인 시 ACCEPTED** | 작성: 2026-09-22 | Owner: AI팀
> **문서 지위: 이 문서는 AI 도메인 재설계의 단일 기준이다.** 이후 모든 AI 작업(데이터·학습·서빙·스키마)은 이 문서를 따르며, 이 문서와 다른 결정은 §13 결정 로그에 날짜와 근거를 남기고 문서를 먼저 고친 뒤 코드를 바꾼다.
> 근거 원문·조사 보고서: 세션 스크래치 `scratchpad/lit/SYNTHESIS.md` (요약은 §12에 수록)
> 대체 대상: ADR-0001(단일 스테이지 v0.1.0), `2026-05-07-yolo-two-stage-design.md`(v0.2.0 구 설계), `training/configs/risk.yaml`

---

## 0. 30초 요약

- **무엇**: 폰으로 찍은 소비판 사진 → 벌 검출(Stage-1) → 벌 크롭을 원본 해상도에서 떠서 감염/비감염 분류(Stage-2) → **VDI(가시 감염 지수)** + 신뢰구간 + tier + 농진청 기준 권장 조치.
- **왜 다시 설계하는가**: (a) 응애 개체는 폰 사진에서 15~25px 하한을 못 넘기고, 같은 데이터에서 벌 단위 분류가 응애 탐지보다 F1 +16%p(Bilik 2021); (b) 현재 v0.1.0은 레시피 유실·tier 경계 불일치·게이트 공백에 더해 **bbox xyxy 오독으로 12배 부푼 박스로 학습**된 상태; (c) 기존 3%/10% "감염률"은 워시 기준 수치를 이미지 지표에 붙인 범주 오류.
- **목표 수준**: "인공지능으로 이런 게 가능하다"는 **시연**. 운영 지연·비용보다 눈에 보이는 정확한 결과가 우선.
- **응애 위치 표시·응애 카운팅·히트맵은 범위 밖** (Phase 2).

## 1. 가정 (바뀌면 §13에 기록하고 재검토)

| # | 가정 | 출처 |
|---|---|---|
| A1 | **비영리 포트폴리오 프로젝트**. AI Hub 이용약관 제15조②·제16조②(영리 금지)는 적용되지 않으며, 데이터 사용에 따른 책임은 프로젝트 소유자가 진다. **상용 전환 시 NIA 사전 승낙 재검토 필수** | 사용자 결정 2026-09-22 |
| A2 | 입력은 **핸드헬드 폰 자유 촬영** + 앱 가이드. 고정 장비 없음 | 사용자 결정 |
| A3 | 자체 현장 데이터 수집·라벨링 없음. **공개 데이터 + AI Hub만** | 사용자 결정 |
| A4 | 학습: RTX 4060 8GB (`ssh beetrain`, C: 411GB 여유 — 사용자 "용량 충분"). 추론: CPU ONNX (기존 서빙 형상 유지) | 환경 |
| A5 | OpenAI 폴백 경로·프롬프트는 이번 재설계에서 변경하지 않음 | 범위 결정 |
| A6 | 71667 Training 셋(206GB)을 1차 데이터로 바로 사용 | 사용자 결정 |

## 2. 범위

**포함**: Stage-1 성충 검출기, Stage-2 감염 분류기, 크롭 파이프라인(xyxy 수정 포함), VDI 집계·CI·tier, `vdi.yaml`, 서빙 엔진 교체, `AnalysisResponse` 스키마 변경과 API/모바일/어드민 동기, 평가셋·회귀 fixture 재구성, ADR-0002.
**제외**: 응애 개체 탐지·위치·카운팅(Phase 2), 유충 감염 트랙(Phase 2), Grad-CAM 히트맵, 워시 보정계수, OpenAI 경로, 모바일 UI 재설계(스키마 동기만), 인프라.

## 3. 출력 계약 (사용자에게 보이는 것)

| 필드 | 정의 | 비고 |
|---|---|---|
| `vdi` | Σ(감염 판정 성충) / Σ(탐지 성충) × 100, 사진 여러 장이면 **카운트 합산** 후 나눔 | "감염률" 아님. 이름·API·DB·DTO 전부 `vdi` |
| `vdi_ci95` | Beta-Binomial 95% 신뢰구간 (Jeffreys prior Beta(0.5,0.5)) | 벌 수 적으면 구간이 넓어짐 — 표시만, 차단 없음 |
| `bee_total` | 탐지 성충 수 | 항상 표시 |
| `bees[]` | `{box(원본 좌표), p_infested, infested(bool)}` | 감염 판정 벌에 박스 |
| `tier` | `low` / `elevated` / `high` — `vdi.yaml` 초기 경계 3 / 10, `calibrated: false` 명시 | "위험(danger)" 단어 사용 안 함 |
| `recommendations` | 농진청 방제 시기 창(3월 중순~4월 초 / 6월 중순~7월 초 / 7월 하순~8월 중순 / 10월 하순~11월 초) + tier별 문구. `elevated`/`high`는 "가루설탕법(설탕 15g+일벌 100마리)으로 확인" | 치료 지시 아님 |
| `model_versions` | `{stage1, stage2}` SemVer | 회귀 추적 |
| `latency_ms` | 측정값 | 게이트 아님 |

**제거**: `infestation_rate`, `risk_score`, `estimated_count`, `low_confidence` 강제 tier clamp, 히트맵.
**게이트 없음**: 벌 수와 무관하게 항상 결과를 낸다(시연 우선). 벌 수 < 300이면 UI에 "표본 적음" 배지만.

## 4. 아키텍처

```
[원본 사진 1~N] ─ EXIF 회전만, 다운스케일 금지, 원본 보존
   ▼ ① 품질 체크(해상도·블러·밝기) → 경고만
   ▼ ② Stage-1 성충 검출: YOLO11s, 1-class `bee`, 입력 긴 변 1280 축소본, conf 0.15(recall 우선)
        벌 수 > 400 또는 원본 > 20MP면 2×2 타일(SAHI) + NMS 병합
   ▼ ③ 박스 → 원본 좌표 역매핑 → 원본에서 크롭(여백 10% 랜덤 지터) → 종횡비 유지 패딩 → 224²
   ▼ ④ Stage-2 감염 분류: ShuffleNet-V2 x1.0 (ImageNet 사전학습), 이진, temperature scaling 보정
   ▼ ⑤ 집계 vdi / CI / bee_total
   ▼ ⑥ tier (vdi.yaml) ▼ ⑦ recommendations (RDA 앵커)
[응답 §3]
```

**결정 근거**
- 벌은 medium 객체라 1280 축소본으로 충분하고(Stage-1), 크롭만 원본에서 뜨면 Stage-2 입력 해상도 손실이 없다 — 해상도 보존과 CPU 예산을 동시에 만족.
- **성충 1-class**: 71667을 xyxy로 바로 읽으면 유충_정상은 셀(116px)·유충_응애는 영역(489px)으로 같은 객체가 아니어서 분류기가 박스 크기로 답을 맞히는 지름길이 생긴다. 유충은 Phase 2.
- Stage-2 백본은 Agronomy 2026(19개 백본 × 12 전처리, 3-fold)에서 ShuffleNet-V2 x1.0이 최고 안정(범위 1.41%p), VarroaNet(SE) 97.28%. MobileNetV3-Small은 대안.
- 입력 224 패딩: 같은 논문에서 **리사이즈 방식이 최대 단일 효과**(d≈1.0), 종횡비 보존이 우세. "28×28 최적"은 feature map 크기 결론이며 입력 크기와 무관.
- 기존 `orchestrator.py`(엔진 주입) 유지. `yolo_engine.py` → `two_stage_engine.py`, `risk.py` → `vdi.py`, `preprocess.py`는 EXIF/회전만.

## 5. 데이터

### 5.1 역할

| 역할 | 데이터 | 규모 | 라이선스 |
|---|---|---|---|
| Stage-1 학습 | **AI Hub 71667** 성충 3클래스 박스 전부 → `bee` | Training 셋 전체(206GB, 312k장) | AI Hub (A1) |
| Stage-1 보조(옵션) | AI Hub 71488 벌 개체 박스(여왕벌·한봉) | 274k장 | AI Hub |
| Stage-2 학습 (주) | **71667** 성충 크롭: `성충_응애`=1, `성충_정상`+`성충_날개불구`=0 | 응애 ≈ 4.5% of 성충 (Sample 56/1,239) | AI Hub |
| Stage-2 학습 (혼합, 결정됨) | **VarroaDataset** (Zenodo 4085044) train split, **EV2** (Zenodo 13771384) | 감염 3,947 / 정상 9,562 (160×280) ; 감염 3,183 / 정상 1,987 | CC BY 4.0 (둘 다 Zenodo 원본 기준; EV2 Kaggle 미러의 NC 표기는 무시) |
| 평가 (인도메인) | 71667 golden 300장 (응애 100 + 정상 200), colony-disjoint, 학습 영구 제외 | 기존 `golden_holdout.py` | |
| 평가 (혼합 도메인) | VarroaDataset 기본 **test split**(감염 942 / 정상 2,466), EV2 hold-out 15% | 학습에서 제외 | |
| 평가 (야외 OOD) | VD2/Vit4V 프레임 — **평가 전용** (CC BY-NC-ND, 학습 금지) | | |
| 제외 | Kaggle "varroa" 업로드 7종(VarroaDataset 복사본·라이선스 위조), Roboflow 재업로드 | | |

### 5.2 71667 파싱 정정 (P0)
- `bbox`는 **`[x1,y1,x2,y2]`**. `aihub_to_yolo.py:150` 수정 + `area` 필드 교차검증 테스트(4,208/4,210 일치 재현).
- xyxy 기준 Sample 통계: 성충_정상 중앙값 263×269px(면적 3.4%), 성충_응애 400×354px(최소 153×139), 유충_정상 116×117, 유충_응애 489×500. → **응애 박스는 벌/영역 크기이며 응애 개체 크기(≈30px)가 아니다 = Q3=B 유지**.
- 71667은 벌 1마리 ≈ 265px @FHD ≈ **22 px/mm**로 근접 촬영. 폰 소비판 한 컷(12MP)의 벌 ≈ 100px보다 2.5배 고해상도 → §6 스케일 증강 필수.

### 5.3 전처리·분할
- `make_crops.py`(신규): xyxy 박스 → 원본 크롭(여백 0~15% 랜덤) → 종횡비 보존 패딩 224 → `crops/{split}/{label}/` + `crops.csv`(원본·colony·device·원 박스 크기). 박스 짧은 변 < 48px 제외.
- 분할은 기존 **per_colony_time_block** 유지(colony 001 = 75%). Stage-1·Stage-2가 **동일 colony split**을 공유해 e2e 누수를 막는다.
- VarroaDataset·EV2는 각자의 공식 split 유지. 학습 시 도메인 혼합 비율은 **실험 변수**(71667 : 외부 = 1:0 / 3:1 / 1:1)로 기록.

## 6. 학습 레시피 (커밋 대상 — 레시피 유실 재발 방지)

| 항목 | Stage-1 (검출) | Stage-2 (분류) |
|---|---|---|
| 모델 | YOLO11s, `yolo11s.pt` 사전학습 | ShuffleNet-V2 x1.0, ImageNet 사전학습, 이진 head |
| 입력 | 1280 (batch 8, AMP) | 224 (batch 128) |
| 최적화 | AdamW lr 1e-3 cos, 100 ep, patience 20 | AdamW lr 3e-4 cos, 50 ep, patience 10, label smoothing 0.05 |
| 불균형 | — | 클래스 가중 CE + 양성 오버샘플(에폭당 1:3), 층화 split |
| 증강 (기하) | mosaic, flip, ±15°, scale 0.5 | flip, ±15° 회전, **스케일 다운 증강: 크롭을 90~265px로 무작위 축소 후 224 재확대**(폰 해상도 모사) |
| 증강 (광도) | hsv_s 0.4 / hsv_v 0.3 / **hsv_h 0.01**, 모션블러, 그림자 | 밝기·대비 ±0.3, CLAHE p0.3, 모션블러 p0.2, 그림자, JPEG 재압축 q50~95, **hue 최소** |
| 금지 | copy_paste(bbox 전용 라벨에서 no-op, 2026-06-08 확인) | 원근·전단 왜곡(응애 형태 단서 손실) |
| 재현성 | `train.py`에 **모든** 하이퍼파라미터 CLI 오버라이드 + run별 resolved config를 `eval_history/<ver>.json`에 동봉 | 동일 |
| 보정 | — | validation으로 temperature scaling, ECE 보고 |

순서: **Stage-2 먼저**(가볍고 빠름 → 조기 신호) → Stage-1 → e2e.
4060 예산: Stage-2 5만 크롭 50ep ≈ 수십 분, Stage-1 5k 이미지 100ep ≈ 수 시간 → 50k 확장은 하룻밤.

## 7. 평가와 게이트

| 수준 | 셋 | 지표 | 게이트 |
|---|---|---|---|
| Stage-1 | 71667 golden | mAP@0.5, recall(`bee`) | mAP@0.5 ≥ 0.85, recall ≥ 0.90 |
| Stage-2 | 71667 golden 크롭 / VarroaDataset test / EV2 hold-out | 감염 recall, 정상 precision, AUROC, ECE | golden 감염 recall ≥ 0.90 & 정상 precision ≥ 0.90 |
| **e2e** | 71667 golden 이미지 | **VDI MAE**, **tier 일치율**, 경계권(2~12%) 부분집합 MAE | tier 일치율 ≥ 0.85 (초기값, 첫 측정 후 고정) |
| OOD | VD2 프레임, BeeImage | Stage-2 recall 하락폭 | 보고만 (−10~15%p 예산) |

- 회귀 fixture(`regression_manifest.json`) 전면 재구성: 경계권·저벌수·`varroa_visible=no`(EV2) 케이스 포함. 기존 24개는 `v0.1.0-single-stage` 태그에 보존.
- 기존 `tier_from_rate`/`tier_from_score` 이중 정의 제거 → `vdi.py` 단일 함수 + 경계 근처 단위 테스트(2.9, 3.0, 3.1, 9.9, 10.0, 10.1).

## 8. 서빙·스키마

- `apps/ai/app/services/two_stage_engine.py`: Stage-1 ONNX(INT8 허용) → 크롭 → Stage-2 ONNX(**FP32 유지**, 소형 특징 보호) 배치 추론. 크롭 수 상한 없음.
- `apps/ai/app/services/vdi.py`: 집계·CI·tier·recommendations. 설정 `training/configs/vdi.yaml`(`thresholds: {elevated: 3, high: 10}, calibrated: false, rda_windows: [...]`).
- `AnalysisResponse`(Pydantic) 변경 → `apps/api/src/services/ai-client.ts`, `packages/types`, `apps/mobile/lib/features/analyses/` DTO, `apps/admin` 진단 뷰 동기. `analyses` 테이블: `vdi numeric`, `vdi_ci_low/high`, `bee_total int` 추가, `varroa_infection_risk`·`estimated_varroa_count`는 nullable 유지 후 다음 마이그레이션에서 제거.
- 가중치: `s3://helpbee-models/yolo/v0.2.0/{stage1,stage2}.onnx` + `metadata.json`(resolved config 포함).

## 9. 이행 순서 (마일스톤)

| # | 작업 | 산출물 | 의존 |
|---|---|---|---|
| 1 | 71667 Training 셋 다운로드 (aihubshell, 사용자 API 키) → `training/datasets/aihub-71667/` | 레이아웃 확인 로그 | 사용자 키 |
| 2 | `aihub_to_yolo.py` xyxy 수정 + area 교차검증 테스트; 성충 1-class 매핑 | PR | — |
| 3 | `make_crops.py` + VarroaDataset·EV2 다운로드·정규화 | `crops/`, `crops.csv` | 1,2 |
| 4 | golden 재추출(xyxy) + colony split | `golden/`, split manifest | 3 |
| 5 | **Stage-2 학습** + 보정 + 평가(golden/VarroaDataset test/EV2) | `eval_history/v0.2.0-stage2.json` | 3,4 |
| 6 | **Stage-1 학습** + 평가 | `eval_history/v0.2.0-stage1.json` | 2,4 |
| 7 | e2e 평가 + 회귀 fixture 재구성 | `regression_manifest.json` v2 | 5,6 |
| 8 | ONNX export + `two_stage_engine.py` + `vdi.py` + 스키마 + 단위 테스트 | PR | 7 |
| 9 | API·types·mobile·admin 스키마 동기 | PR | 8 |
| 10 | ADR-0002 + `apps/ai/CLAUDE.md`·`AIHUB_71667.md` 정정 + v0.1.0 태그 | PR | 8 |

## 10. 리스크

| 리스크 | 완화 |
|---|---|
| 리그(22px/mm)→폰(≈9px/mm) 스케일·조명 갭 미측정 | §6 스케일 다운 증강 + 광도 증강, VD2 OOD 보고, 시연 촬영 조건(밝은 그늘, 반 소비판, 12MP+) 사전 고정 |
| 71667 응애 4.5% 불균형 | 가중 CE + 오버샘플 + 외부 양성 혼합(결정됨) |
| 응애 박스가 정상 벌 박스보다 큼(400 vs 263) → 크기 지름길 | 여백 랜덤 지터 + 스케일 증강으로 절대 크기 정보 제거; 검증에서 박스 크기별 recall 분해 |
| 206GB 다운로드·해제 (학교망 속도, 디스크) | 순차 zip 처리·해제 후 zip 삭제; 사용자가 용량 충분 판단 |
| 스키마 변경 파급(4개 앱) | `packages/types` 단일 소스에서 시작, 필드 추가 먼저·제거는 다음 마이그레이션 |
| tier 경계가 미보정 초기값 | UI·API에 `calibrated: false` 노출, "확인하세요" 문구 |

## 11. Phase 2 후보 (범위 밖, 기록만)
- 약지도 응애 위치: `성충_응애` 크롭 = MIL 양성 bag → Grad-CAM++ 피크 → P2BNet(point→box) → 크기 prior(응애 = 벌 장축 8~13%) → VarroaDataset 응애 박스 4,628개와 결합.
- 유충 트랙(셀 단위 vs 영역 단위 라벨 정합 후).
- DINOv2 클릭 프로브: 폰 해상도에서 응애 특징 존재 여부 go/no-go.

## 12. 근거 요약 (검증 등급: ✅ 원문 확인 / 🟡 보고서)

- ✅ Bilik 2021 (Sensors 21:2764): 응애 15~25px@640 설계 기준; 감염 벌 F1 0.874 vs 응애 F1 0.714; "감염은 몸 변형과 연결되고 응애가 항상 보이지 않아 벌 단위 분류가 더 강건할 수 있다".
- ✅ Lee et al. 2025 (Agriculture 15:1221, 강원대·농과원): FLIR 2048×1536 @300mm 고정, 640 ROI, YOLOv7; 감염 벌 98.2% ≈ 응애 개체 98.0%; 증강 = 정규화+CLAHE, 층화 split; 데이터 비공개.
- ✅ Agronomy 2026 16:1292 (같은 팀): 20봉군 3,400 ROI(1,700/1,700), 원본 ROI 40×39~344×302, 224 패딩; 리사이즈 최대 효과(d≈1.0), 디블러 비유의; ShuffleNet-V2 최고 안정, VarroaNet 97.28%.
- ✅ JKSCI 2024: Stage-2(91%)는 Zenodo 입구터널 크롭 학습·평가, 집계 미정의, e2e 없음.
- ✅ Liu/Bilik 2023 (AgriEngineering 5:102): 입구 4K 고정, FCN→YOLOX+CA, 응애 100마리 합성; 야외 조명에서 취약한 건 분할(Stage-1) 단계.
- ✅ VarroaDataset gt.csv: 라벨 0/1/3, 1+3 = 3,947 감염, 응애 박스 4,628(중앙값 32×31).
- ✅ 71667 Sample xyxy 재계산: §5.2.
- 🟡 이미지 지표↔워시 대조 검증 논문 0편; 육아기 응애 ~2/3 봉개 유충방 내; n≥300에서 3% 구분(±1.9%p) — infestation-rate 보고서.
- 🟡 농진청 방제 시기·월동 전 10%·가루설탕법 — RDA 보도자료.
- 🟡 BeeSion(농진청×강원대) 97.8%, ₩400만 장비 — 고정 리그 경쟁 제품.

## 13. 결정 로그

| 날짜 | 결정 | 근거 |
|---|---|---|
| 2026-09-22 | 목표 = 실제 벌 개체별 응애 감염 판정(실전 진단 시연) | 사용자 |
| 2026-09-22 | 응애 bbox 탐지가 아니라 **벌 크롭 → 감염 분류** | 사용자 제안 + Bilik 2021 |
| 2026-09-22 | 핸드헬드 폰 자유 촬영 | 사용자 |
| 2026-09-22 | 비영리 포트폴리오 전제, 데이터 책임 소유자 부담 | 사용자 |
| 2026-09-22 | 벌 수 게이트 제거(시연 우선), 히트맵 제외 | 사용자 |
| 2026-09-22 | `infestation_rate`→`vdi`, tier `low/elevated/high` | 승인 |
| 2026-09-22 | VarroaDataset·EV2를 Stage-2 학습에 혼합; 1차 데이터 = Training 셋; 평가 = Zenodo test split + 71667 golden | 사용자 |
| 2026-09-22 | Stage-1 성충 1-class, 유충 Phase 2 | xyxy 재계산(§5.2) |

## 14. 미해결
- 71667 Training 셋 다운로드 소요 시간(학교망) — 1차 실행에서 측정.
- 도메인 혼합 비율(§5.3) — 실험으로 결정, 결과를 §13에 기록.
- tier 경계 3/10의 유지 여부 — e2e 첫 측정 후 결정.
- 4개 앱 스키마 동기 PR 분할 단위.
