# HelpBee AI 재설계 — 2-Stage 벌 단위 감염 분류 + VDI 지표 (v0.2.0 목표) — **v2**

> **Status: ACCEPTED (v2.2, 사용자 승인 2026-09-25)** | v1: 2026-09-22 | v2: 2026-09-23 (적대적 검증 반영) | v2.1: 2026-09-23 (2차 검증 반영) | v2.2: 2026-09-25 (v0.2.0 결과 반영 — τ 정책·크기 게이트·cal 다양성·Stage-2 백본, §13) | Owner: AI팀
> **문서 지위: 이 문서는 AI 도메인 재설계의 단일 기준이다.** 이후 모든 AI 작업(데이터·학습·서빙·스키마·모바일 캡처)은 이 문서를 따르며, 다른 결정은 §13 결정 로그에 날짜와 근거를 남기고 **문서를 먼저 고친 뒤 코드를 바꾼다.**
> v1 → v2 변경 근거: [`2026-09-23-ai-two-stage-redesign-adversarial-review.md`](2026-09-23-ai-two-stage-redesign-adversarial-review.md) (차단 7 · 주요 16 · 기각 1)
> 대체 대상: ADR-0001, `2026-05-07-yolo-two-stage-design.md`, `training/configs/risk.yaml`

---

## 0. 30초 요약

- **무엇**: 폰으로 찍은 소비판 사진 → 성충 검출(Stage-1) → 벌 크롭을 **원본 해상도**에서 떠서 감염/비감염 분류(Stage-2) → **VDI(가시 감염 지수, 분류기 오차 보정)** + 표본 신뢰구간 + tier + 시각 증거(감염 판정 크롭 갤러리 + 주목 영역) + 농진청 기준 권장 조치.
- **왜 2-stage인가 (v2에서 명시)**: (a) 상용 가능한 외부 감염 라벨 데이터(VarroaDataset·EV2)는 **벌 크롭**이라 분류기만 학습시킬 수 있다; (b) 크롭을 원본에서 뜨면 Stage-2 입력 해상도 손실이 없다; (c) Bilik 2021에서 벌 단위 판정이 응애 개체 탐지보다 F1 +16%p. 단, **xyxy 수정 + 성충 2-class 단일 YOLO**도 같은 출력을 내므로 §7에 e2e 베이스라인으로 두고 이겨야 한다.
- **왜 다시 만드는가**: v0.1.0은 bbox xyxy 오독(12배 부푼 박스), 레시피 유실, tier 경계 불일치, 게이트 공백. "감염률 3%/10%"는 워시 수치를 이미지 지표에 붙인 범주 오류.
- **목표 수준**: "AI로 이런 게 가능하다"는 **시연**. 단, v2는 시연이 **거짓 양성으로 무너지지 않도록** 보정·게이트를 넣는다.
- **범위 밖**: 응애 카운팅·워시 보정·유충 트랙(Phase 2).

## 1. 가정

| # | 가정 | 출처 |
|---|---|---|
| A1 | **비영리 포트폴리오 프로젝트**. AI Hub 영리 금지 조항 비적용, 데이터 책임은 소유자. 상용 전환 시 NIA 사전 승낙 재검토. 레포의 유료 티어·가격 페이지는 **portfolio 모드 플래그로 비활성**(§8) | 사용자 2026-09-22 |
| A2 | **핸드헬드 폰 자유 촬영 + 앱 가이드.** 앱은 **최대 해상도로 캡처하고 원본 크기로 업로드**(≥12MP 목표, 10MB 초과 시에만 긴 변 4000으로 축소). 현재 720p 캡처·1920 축소는 폐기 | 사용자 + 검증 B1 |
| A3 | 자체 현장 데이터 수집·라벨링 없음. 공개 데이터 + AI Hub만. **예외(소유자 승인 필요)**: Gate 0(a)용 소비판 폰 사진 5장 — 라벨링 없이 벌 px 실측·밀집 recall 확인용. 출처는 부스·지인 양봉장 등 어디든 | 사용자 + 2차 검증 N7 |
| A4 | 학습: RTX 4060 8GB **네이티브 Windows**(WSL2 불가), C: 411GB + **D: ~444GB(미할당 영역 신설)**. 디스크 예산은 §5.3 표를 따른다. 추론: CPU ONNX, beta EC2 t3.medium(ai `mem_limit 1536m`) | 환경 + 검증 M8 |
| A5 | **OpenAI 폴백은 이번 범위에서 동결(shim)**: `risk.py`/`risk.yaml`을 OpenAI·부스 전용으로 남기고, OpenAI 결과는 `rate → vdi/tier` 매핑으로 새 계약을 채운다(`bees[]` 없음, `bee_total:null`). v1의 "변경 없음"은 철회 | 검증 B6 |
| A6 | 71667 Training 셋(206GB)은 D:에 받되, **Stage-2와 파이프라인 검증은 Validation 셋(26GB)+외부 데이터로 먼저** 시작 | 검증 M16 |

## 2. 범위

**포함**: 모바일 캡처·업로드 해상도(B1), API 이미지 패스스루, Stage-1/Stage-2, 크롭 파이프라인(xyxy), VDI 집계·보정·CI·tier, `vdi.yaml`, 서빙 엔진, 시각 증거, 스키마 이중 출력 이행(B7), 4개 앱 동기, 부스 앱 JSON 동결, 평가셋·회귀 fixture 재구성, Windows 툴체인, ADR-0002.
**제외**: 응애 위치·카운팅, 워시 보정, 유충 트랙, OpenAI 프롬프트, 인프라 변경(단 §8의 시연 인스턴스 권고는 기록).

## 3. 출력 계약

| 필드 | 정의 |
|---|---|
| `vdi` | **보정 지수** (Rogan–Gladen): 점추정 = `clip((raw − FPR) / (TPR − FPR), 0, 100)`. raw = k/n×100, k = τ 초과 성충 수, n = 탐지 성충 수. TPR/FPR은 **cal-B 절반**(§5.1)의 측정값을 `vdi.yaml`에 고정. τ는 cal-A에서 **TPR − FPR 최대점(Youden), 단 cal-A FPR ≤ 10%**(v2.2, §5.1). `TPR − FPR < 0.5`면 보정 불가 → `vdi = raw`, `corrected:false` |
| `vdi_display` | AI가 **한 번만** 반올림한 문자열(`Decimal(repr).quantize('0.1', ROUND_HALF_UP)`). 클라이언트는 재반올림 금지. **tier는 이 값에서만 계산** |
| `bee_infested` | k (raw 양성 수). N장 합산·재계산의 원천 |
| `vdi_raw` | 보정 전 값 (`raw_payload`) |
| `sampling_ci95` | **raw k/n에 Jeffreys 이항 구간**을 구한 뒤 양 끝점을 Rogan–Gladen으로 사상(점추정만 clip, 구간은 하한 0 floor만). 건강 벌통에서 [0,0] 붕괴 금지 — 상한은 raw 상한 이상. UI 라벨 **"표본 신뢰구간(분류기 오차 미포함)"** |
| `bee_total` | 탐지 성충 수. `< 30`이면 "표본 적음" 배지 |
| `bees[]` | `{box(원본 좌표), p_infested, infested(bool)}` |
| `evidence[]` | 감염 판정 상위 k=6 크롭(원본 해상도 확대) + **CAM 오버레이**(닫힌 형식, §4 ⑦). UI 표기 **"주목 영역 (응애 위치 아님)"** |
| `tier` | `low` [0,3) · `elevated` [3,10) · `high` [10,∞) — **반열림, `vdi_display` 기준** (테스트: 2.949→2.9 low / 2.95→3.0 elevated / 9.95→10.0 high) · `insufficient` = `bee_total == 0` 또는 `quality.ok == false` (벌이 있어도 `vdi`는 채우되 tier만 insufficient) · `tier_legacy` = low→safe, elevated→watch, high→danger, insufficient→unknown |
| `quality` | `{blur_score, exposure_mean, px_per_mm_est, ok:bool}` — 초기 임계: 1024 축소본 Laplacian 분산 < 100 → 블러 실패; 평균 밝기 ∉ [40, 215] → 노출 실패; `px_per_mm_est`(중앙값 벌 폭/12mm) < Gate 0 하한 → **경고만**. 값은 `vdi.yaml` |
| `recommendations` | tier별 문구 + **"다음 권장 점검 시기"**(RDA 창) — `low`에는 방제 문구 없음. `elevated/high`는 "가루설탕법(설탕 15g+일벌 100마리)으로 확인". severity: low→info, elevated→warn, high→danger, **insufficient→info** |
| `model_versions` | `{stage1, stage2, vdi_config}` |
| `latency_ms` | 측정값 |

**항상 결과를 낸다**(박스·크롭은 표시). `insufficient`는 게이트가 아니라 0으로 나눌 수 없거나 사진이 판독 불가일 때의 tier다. **수용한 리스크(소유자 결정)**: 벌 1마리 감염이면 100% `high`가 표시된다 — 배지와 CI로만 완화. tier는 CI가 아니라 점추정으로 정한다. 화면에 **"보정 전 시험 지표 — 사진은 봉개 유충방 속 응애를 볼 수 없습니다"** 고정 문구.

## 4. 아키텍처

```
[폰 캡처 ResolutionPreset.max → HEIC는 JPEG 변환(축소 없음) · GPS strip 유지 → 원본 업로드(≤10MB, 초과 시만 긴 변 4000)]
   ▼ API: sharp는 EXIF 회전·strip, **치수 유지, JPEG q95**(현행 q85 폐기), limitInputPixels 50MP
   ▼ AI: `MAX_EDGE=1024` 축소는 **two-stage 경로에서만 우회** (v0.1.0 YOLO·OpenAI 경로는 그대로)
   ▼ ① 품질 체크: 블러(Laplacian var)·노출·해상도 → quality.ok; 실패 시 tier=insufficient (박스는 계속)
   ▼ ② Stage-1 성충 검출: YOLO11s 1-class `bee`, 입력 1024, **≥8MP면 항상 2×2 타일(SAHI)**, max_det 1500, conf 0.15, 타일 병합은 IoMin NMS
   ▼ ③ 박스 → 원본 좌표 → 원본 크롭(여백 10% 고정) → 종횡비 유지 패딩 → 320 (v2.2; v2.1은 224)
   ▼ ④ Stage-2 분류: **ResNet-18**(v2.2; v2.1 ShuffleNet-V2 x1.0), 64개씩 청크 추론, p = Platt(bias 포함) 보정, infested = p > τ(vdi.yaml)
   ▼ ⑤ 집계: raw → Rogan–Gladen 보정 vdi, Jeffreys CI, bee_total
   ▼ ⑥ tier(반열림, 표시값 기준) ▼ ⑦ evidence: top-k 크롭 + **CAM(닫힌 형식)** — Stage-2 ONNX에 마지막 conv feature map을 2번째 출력으로 내보내고 GAP→FC 가중치로 계산(그래디언트 불필요) ▼ ⑧ recommendations
```

**결정 근거(v2)**
- 벌은 medium 객체라 1024 축소본으로 찾고 크롭만 원본에서 뜬다. 서빙 벌 크기(≈100px @12MP → 1024에서 ≈30px)와 학습(71667 265px @FHD)의 **5× 스케일 갭**은 (i) ≥8MP 항상 타일, (ii) Stage-1 scale 증강 0.15, (iii) 밀집 데이터 71488 필수로 메운다.
- 성충 1-class: 유충_정상(셀 116px)과 유충_응애(영역 489px)는 다른 객체. 유충은 Phase 2.
- **Stage-2 크롭은 Stage-1 예측 박스에서 만든다**(GT 박스 아님): GT 응애 박스가 정상보다 크고(413 vs 325px) 이웃 벌을 포함(31/56)하는 지름길을 끊기 위해. 따라서 **Stage-1을 먼저 학습**한다.
- 분류기 백본: Agronomy 2026에서 ShuffleNet-V2 x1.0이 전처리 변동에 가장 안정(범위 1.41%p, **가시 응애만 큐레이션한 인디스트리뷰션 결과**). 224 패딩: 리사이즈 표준화가 최대 효과(d≈1.0)이며 **MR/NR 방식 간 유의차는 없음(p=0.376)**. 28×28 feature map 결론은 응애가 224 입력에서 10~20px일 때의 결과 — 우리는 Gate 0에서 실제 px를 확인한다.
- **v2.2 (2026-09-25) 백본 확정**: v0.2.0 최종 Stage-2 = **ResNet-18, 320px 크롭, 모델 선택은 cal-A AUROC 기준**. ShuffleNet-V2 x1.0 @224는 변형 3종 모두 게이트 실패(cal-B TPR ≤ 0.27). ShuffleNet은 CPU 예산이 더 빡빡할 때의 **문서화된 폴백**으로 유지. 서빙: ResNet-18 CPU ≈ **15 ms/크롭 @320px**; ONNX 출력 계약 불변(`logit`, `featmap` — 이제 512ch); CAM은 `fc_weight` 길이를 `metadata.json`에서 읽는다.
- 기존 `orchestrator.py` 엔진 주입 유지. `two_stage_engine.py` 신설, `vdi.py` 신설, `risk.py`는 OpenAI·부스용 shim으로 동결.

## 5. 데이터

### 5.1 역할

| 역할 | 데이터 | 규모 · 비고 |
|---|---|---|
| Stage-1 학습 | **71667** 성충 3클래스 → `bee` **상한 2.5만 장**(colony·device 층화) + **71488 필수**(밀집·여왕벌·한봉) | 312k 전체는 4060에서 수 주 — 상한 |
| Stage-2 학습 (인도메인) | 71667 성충 크롭 — **out-of-fold Stage-1 예측 박스**(2-fold: A로 학습한 Stage-1이 B를 예측, 반대도) GT IoU≥0.5 매칭 기준 — 학습 이미지 자체 예측은 과적합으로 박스가 타이트해 서빙과 불일치. `성충_응애`=1, `성충_정상`=0. **`성충_날개불구`(DWV)는 제외**. **감염 이미지 안의 정상 박스는 학습 음성에서 제외**(미검증 음성). 착수 전 **감염 이미지 내 정상 크롭 100개 육안 감사**로 노이즈율 기록 | 라벨 노이즈 차단 |
| Stage-2 학습 (외부 혼합) | VarroaDataset train, EV2 train | **소스별 양성 prior를 균등 샘플링**, 71667과 같은 패딩·종횡비로 재크롭 |
| **cal split** | 71667 colony-disjoint 15%를 **colony 단위로 반분**: **cal-A** = Platt(bias 포함) 보정 + τ 결정 — **τ = cal-A에서 TPR − FPR 최대점(Youden), 단 cal-A FPR ≤ 10% 상한** (`tau_policy: youden`, `fpr_cap: 0.10`; v2.2, v2.1의 'FPR 1% 목표'를 대체), **cal-B** = 그 τ에서 TPR/FPR 측정(→ `vdi.yaml`); 보정 조건 `TPR − FPR ≥ 0.5` 불변. `vdi.yaml`에 `tau_policy`, `fpr_cap`, **τ에서의 cal-A FPR**을 반드시 기록. 음성 정의는 학습과 동일(DWV·감염 이미지 내 정상 박스 제외). **다양성 제약(v2.2, 다음 데이터 확장부터)**: cal-A·cal-B 각각 **≥ 3 colony**(현재 각 2; Training 단계 동결이 최종이므로 지금 재동결하지 않음) | in-sample 보정 방지 |
| golden (학습 영구 제외) | 71667 **colony × 날짜 블록 홀드아웃**, 선택은 원본 JSON `category_id==5`, colony·device당 **≥10분 디듀프**, 응애 이미지 100 + 정상 이미지 200(성충 포함 필수). 음성 정의 학습과 동일. **golden colony 목록은 Validation·Training 셋 합집합 기준으로 3단계에서 동결**하고 변경 시 테스트 실패 | `has_varroa_label()` 재작성 |
| 평가 (혼합) | VarroaDataset test split, EV2 hold-out 15% | |
| 평가 (야외 OOD, 평가 전용) | VD2 프레임, BeeImage | 라이선스상 학습 금지 |
| e2e 평가 | golden 벌 크롭(성충 박스 단위, 라벨 유지)을 **층화 부트스트랩**으로 재조합해 목표 VDI 0 / 2 / 5 / 12 / 20%의 **합성 의사-프레임**(각 300 성충, 목표당 ≥40 프레임). "합성"임을 보고서에 명시. **폰 도메인 정확도는 미측정**임을 §7·UI에 명시 | golden 원천만으로는 0% 프레임 부족(감염 100% colony 존재), 이미지당 성충 중앙값 4마리 |

### 5.2 71667 파싱 정정 (P0)
- `bbox` = **`[x1,y1,x2,y2]`**. `aihub_to_yolo.py:150` 수정 + `area` 교차검증 테스트(4,208/4,210 재현).
- xyxy Sample 통계: 성충_정상 263×269(면적 3.4%), 성충_응애 400×354(긴 변 하위 10% 338 > 정상 중앙값), 유충_정상 116×117, 유충_응애 489×500. 응애 박스는 벌 단위(다른 성충 50% 이상 포함 2/56)이나 느슨함.
- 71667 = 벌 265px @FHD ≈ 22 px/mm 근접 촬영. 폰 12MP 소비판 한 컷 ≈ 9 px/mm.
- **감염 벌 56/56 `state=정상`** — 형태 단서 없음. 분류기가 볼 수 있는 건 응애뿐 → §7 Gate 0.

### 5.3 전처리·분할·디스크
- **디스크 예산** (분할 zip은 부분 해제 불가 → zip과 해제본이 동시에 존재):

| 단계 | D: (444) | C: (411) |
|---|---|---|
| 71667 TS zip | 206 | |
| 71667 TS 해제 | | 206 (원본 그대로 두고 manifest로 참조) |
| zip 삭제 후 | 0 → 444 여유 | |
| 71488 (**서브셋만**; 원본 274k장 추정 100~140GB — AI Hub 페이지에서 실크기 확인 후 결정) | ≤150 | |
| VarroaDataset + EV2 + VD2 프레임 + BeeImage | ~10 | |
| 크롭·manifest·runs | | ~30 |

- 변환·split·golden은 **복사 대신 manifest(txt 이미지 목록)** — `copy_images=False` 기본화, Windows 개발자 모드 symlink 불필요.
- 분할: 기존 `per_colony_time_block`은 **train/val용**으로만 쓰고, golden·cal은 colony 단위 홀드아웃. Stage-1·Stage-2·cal·golden이 **하나의 `split_manifest.json`**을 읽고 테스트가 disjoint를 검사.
- Windows: `PYTHONUTF8=1`, 모든 `read_text/open`에 `encoding="utf-8"`, `make` 대신 `tasks.py`(PowerShell 호환), 7-Zip UTF-8 해제 후 `01.원천데이터` 폴더명 assert, `workers: 4`.

## 6. 학습 레시피 (커밋 대상)

| 항목 | Stage-1 (검출) | Stage-2 (분류) |
|---|---|---|
| 모델 | YOLO11s, `yolo11s.pt` | **ResNet-18**, ImageNet, 이진 head, 모델 선택 = cal-A AUROC (v2.2; 폴백 ShuffleNet-V2 x1.0) |
| 입력 | 1024, `batch: -1`(autobatch), AMP | **320** 패딩(v2.2; v2.1 224), batch 128 |
| 데이터 | 71667 2.5만 + 71488 | §5.1 |
| 최적화 | AdamW 1e-3 cos, 100 ep, patience 20 | AdamW 3e-4 cos, 50 ep, patience 10 |
| 불균형 | — | **가중 샘플러만**(가중 CE·오버샘플 동시 사용 금지) |
| 스케일 증강 | scale **0.15~1.0**, 다중 이미지 축소 모자이크 | **폰 열화 파이프라인**: 광학 블러 → 축소(벌 긴 변 **Gate 0 하한~265px**) → 센서 노이즈 → 언샤프 → JPEG q50~95 → 320 재확대(v2.2) |
| 광도 증강 | hsv_s 0.4 / hsv_v 0.3 / **hsv_h 0.01**, 모션블러, 그림자 | 밝기·대비 ±0.3, CLAHE p0.3, 그림자, **hue 최소** |
| 기하 | mosaic, flip, ±15° | flip, ±15°, **약한 원근 ≤10°** (핸드헬드 사각) |
| 금지 | copy_paste(bbox 라벨 no-op) | 강한 전단·원근 |
| 보정 | — | **Platt(bias 포함)** on cal-A(자연 유병률) → τ = cal-A **Youden 최대점(TPR − FPR), cal-A FPR ≤ 10%** (`tau_policy: youden`, `fpr_cap: 0.10`) → cal-B에서 TPR/FPR 측정 → `vdi.yaml`(τ·`tau_policy`·`fpr_cap`·τ에서의 cal-A FPR 포함) |
| 재현성 | `train.py` 전체 하이퍼파라미터 CLI + resolved config → `eval_history/<ver>.json` | `train_stage2.py` 동일 |

순서: **Stage-1(2-fold) → out-of-fold 크롭(사전 추출) → Stage-2 원본 크롭 학습(Gate 0(b)용) → Gate 0(b) → Stage-2 최종(열화 증강) → cal-A/cal-B → e2e.** 4060 예산(실측 전 추정): Stage-1 2.5만장 100ep@1024 ≈ **2~4일**(+71488 시 추가), Stage-2 50ep ≈ **3~8시간**(열화 파이프라인이 CPU 병목). 첫 epoch 실측 후 갱신.

## 7. 평가와 게이트

| 게이트 | 내용 | 통과 기준 |
|---|---|---|
| **Gate 0** | (a) 실제 앱 업로드 소비판 사진 5장(A3 예외)에서 벌 px 실측 + 손 카운트 recall; (b) **Stage-2를 원본 크롭으로 먼저 학습**한 뒤 px/mm 22→15→12→9 시뮬 recall 곡선; (c) DINOv2 클릭 프로브 | recall 붕괴 지점을 **촬영 가이드 하한**으로 확정하고 §6 축소 하한을 그 값으로 고정. 12MP 한 컷이 하한 미달이면 "반 소비판 촬영"을 가이드 기본으로. **반 소비판으로도 미달이면 스펙 재검토(§13 기록) — 그 상태로 시연 진행 금지** |
| Stage-1 | golden mAP@0.5, `bee` recall; 밀집 폰 프레임(손 카운트 5장) recall 보고 | mAP ≥0.85, recall ≥0.90 |
| Stage-2 | golden 크롭 감염 recall, **specificity**, AUROC, ECE; **소스·기기·colony별 분리 보고**; 임베딩→소스 선형 프로브; leave-one-device-out. **진단(보고만, v2.2)**: 크기·종횡비만 로지스틱 베이스라인 AUROC(라벨=GT 박스 크기의 성질이지 모델 성질이 아님 — 증강과 무관하게 golden 0.79 / EV2 0.85 실측), **native 크기 3분위별 recall@τ**(임계값 없음) | recall ≥0.90 **& specificity ≥0.985** @τ; 100 양성 기준 CI(±0.06) 명시 |
| e2e | 의사-프레임 VDI MAE, **tier 혼동행렬**, 사소 베이스라인(전부 low) 병기; **0% 감염 의사-프레임 → VDI<3 in ≥95%**; **단일 스테이지(xyxy 수정·2-class·1024 타일) 베이스라인 대비** | tier 일치율 ≥0.85 **and** 베이스라인 대비 우세 |
| OOD | VD2·BeeImage에서 recall·**FPR** 하락폭 | 보고만(−10~15%p 예산). **폰 도메인 정확도는 이 스펙 범위에서 측정되지 않는다** — 보고서·UI 고정 문구 |
| 회귀 | `regression_manifest.json` v2: 경계권·저벌수·`varroa_visible=no`·0마리·블러 케이스 | tier 변동 0 |

`vdi.py` 단일 tier 함수 + 경계 테스트(2.949→low, 2.95→elevated, 3.0→elevated, 9.95→high, 10.0→high; `vdi_display` 기준, Decimal ROUND_HALF_UP). `_needs_fallback`(유료 티어 전용, 기존 정책) = `quality.ok == false` 또는 `bee_total < 30`.

## 8. 서빙·스키마·이행 (B7 순서)

1. **API/DB 관용화 먼저**: `failed`는 `engine_used===null`로만; tier 매핑에 `low/elevated/high/insufficient` 추가(`overall_health`: low→healthy, elevated→warning, high→critical, insufficient→null; severity 동일 규칙); `analyses`에 `vdi numeric, vdi_ci_low, vdi_ci_high, bee_total int, bee_infested int` 추가(nullable); `ai_models`에 `('yolo','helpbee-two-stage','0.2.0')` row; 트렌드는 **two-stage row는 `vdi` 시리즈, 구 row는 `varroaInfectionRisk` 시리즈로 분리**(단위가 다르므로 coalesce 금지); severity insufficient→info.
2. **AI 이중 출력** 한 릴리스: 새 필드 + **`risk_score := risk.py score_mapping(vdi)`**(0~100 **점수** 단위 유지 — 10%→70) + `tier_legacy`(§3). `round(vdi)`를 `risk_score`에 넣지 않는다.
3. **소비자 이전**: mobile DTO·화면(`elevated` 화면 정의), admin 진단 뷰, booth는 **JSON 동결**(`make_booth_cases.py`는 `risk.py` shim 사용).
4. **구 필드 제거** 마이그레이션.

- 서빙: Stage-1 ONNX(INT8 허용) → 크롭 → Stage-2 ONNX FP32 **64개 청크**(2번째 출력 = 마지막 conv feature map); 소프트 크롭 상한 1,500(초과 시 랜덤 샘플, `raw_payload`에 기록); CAM은 top-k에만. **타임아웃 체인**: 모바일 `receiveTimeout` **≥95s**(현행 30s) ≥ ai-client two-stage 경로 **90s** ≥ AI 내부 예산. 시연 인스턴스는 **T3 Unlimited 또는 c6i.large** 권고(≈450 GFLOP/요청, 크레딧 소진 시 30~60s).
- **N장 합산**: 저장은 이미지당 row 유지, **읽기 시 집계** `GET /v1/analyses/aggregate?ids=…` — `Σbee_infested / Σbee_total` 원시 카운트로 raw를 만든 뒤 보정·CI·tier를 재계산(저장된 `vdi`는 clip돼 역산 불가). 동일 면 중복 촬영은 UI 문구로 안내.
- **OpenAI shim 계약**: OpenAI rate → `vdi_raw`, `corrected:false`, `bee_total/bee_infested/sampling_ci95 = null`, tier는 같은 반열림 규칙. 폴백 트리거는 §7.
- 가중치: `s3://helpbee-models/two-stage/v0.2.0/{stage1.onnx,stage2.onnx,vdi.yaml,metadata.json}`; 로더에 `TWO_STAGE_MODEL_VERSION` 추가.
- portfolio 모드: `PORTFOLIO_MODE=true`면 유료 플랜·402 쿼터 비활성.

## 9. 이행 순서 (크리티컬 패스 명시)

| # | 작업 | 병렬 | 의존 |
|---|---|---|---|
| 0 | D: 파티션, Python 환경(Windows), `PYTHONUTF8`, `tasks.py` | — | — |
| 1a | 71667 **Validation 셋** + VarroaDataset + EV2 + **VD2 프레임·BeeImage(평가용)** + **71488 서브셋**(실크기 확인 후) | 1b와 병렬 | 0 |
| 1b | 71667 Training 셋(206GB) → D: | 백그라운드 | 0 |
| 2 | `aihub_to_yolo.py` xyxy + area 테스트 + 1-class + manifest 모드 | | 0 |
| 3 | `split_manifest.json`(train/val/cal-A/cal-B/golden colony 홀드아웃; **Validation+Training 합집합 colony 기준으로 golden·cal colony 동결** + 불변 테스트) + golden 재작성 | | 1a, 2 (1b는 colony 메타만 선확보) |
| 4 | **모바일 캡처 max + HEIC→JPEG 무축소 + 원본 업로드 + API q95 패스스루** (B1) → **Gate 0(a)** 실측(A3 예외 사진 5장). AI 축소 우회는 9단계 two-stage 엔진에서 | 3과 병렬 | 소유자 사진 |
| 5 | Stage-1 **2-fold** 학습(Validation 셋 5k로 파이프라인 검증 → 1b 도착 후 2.5만+71488) | | 3 |
| 5.5 | out-of-fold 예측 박스 크롭(사전 추출) → Stage-2 원본 크롭 학습 → **Gate 0(b)(c)** → 촬영·축소 하한 확정 | | 5 |
| 6 | Stage-2 최종 학습(열화 증강, ResNet-18 @320) + cal-A(Platt, τ = Youden·FPR ≤ 10%) + cal-B(TPR/FPR) → `vdi.yaml`(`tau_policy`·`fpr_cap`·cal-A FPR@τ 기록) | | 5.5 |
| 7 | e2e 의사-프레임 평가 + 단일 스테이지 베이스라인 + 회귀 fixture v2 | | 6 |
| 8 | API/DB 관용화(§8-1) | 5~7과 병렬 | — |
| 9 | `two_stage_engine.py` + `vdi.py` + evidence + 이중 출력(§8-2) | | 7, 8 |
| 10 | 소비자 이전(§8-3: 모바일 DTO·`elevated`/`insufficient` 화면·**receiveTimeout ≥95s**, admin, booth 동결) + 구 필드 제거(§8-4) | | 9 |
| 11 | ADR-0002 + `AIHUB_71667.md`·`apps/ai/CLAUDE.md` 정정 + v0.1.0 태그 — **코드 전 문서 갱신 원칙에 따라 각 단계 PR에 포함** | | — |

## 10. 리스크 (v2 잔여)

| 리스크 | 완화 |
|---|---|
| Gate 0에서 12MP 한 컷이 하한 미달 | 반 소비판 촬영 가이드 기본화; 시연 촬영 조건 사전 고정 |
| 예측 박스 기반 크롭이 Stage-1 품질에 종속 | Stage-1 recall 게이트 선행; GT 매칭 실패 박스는 학습 제외 |
| 소스·colony 지름길 잔존 | 소스 프로브·분리 지표가 게이트 |
| 학교망 206GB 다운로드 시간 | Validation 셋 우선 경로(1a) |
| t3.medium 메모리·크레딧 | 청크·상한·시연 인스턴스 권고 |

## 11. Phase 2 후보
약지도 응애 위치(MIL → Grad-CAM++ → P2BNet → VarroaDataset 4,628 박스) · 유충 트랙 · 워시 보정 · 응애 카운팅.

## 12. 근거 요약 (검증 등급 ✅ 원문 / 🟡 보고서)
- ✅ Bilik 2021: 응애 15~25px@640; 감염 벌 F1 0.874 vs 응애 0.714.
- ✅ Lee 2025 (Agriculture 15:1221): FLIR 2048×1536 @300mm 고정, 640 ROI, YOLOv7, 감염 벌 98.2 ≈ 응애 98.0, 정규화+CLAHE, 층화 split, 데이터 비공개.
- ✅ Agronomy 2026 16:1292: 20봉군 3,400 ROI(가시 응애만 큐레이션), 원본 ROI 40~344px, 224 패딩; 리사이즈 표준화 최대 효과(d≈1.0), **MR vs NR 유의차 없음(p=0.376)**; **응애가 224 입력에서 10~20px일 때 28×28 feature map 최적**; ShuffleNet-V2 x1.0 전처리 민감도 최저(1.41%p), VarroaNet 97.28%. 3-fold random CV(colony 비분리).
- ✅ JKSCI 2024: Stage-2는 Zenodo 입구 크롭 학습·평가, 집계 미정의.
- ✅ **Liu et al. 2023** (AgriEngineering 5:102): **벌통 입구** 4K 고정, FCN→YOLOX+CA, 응애 100마리 합성, 야외 조명 취약 단계 = 분할.
- ✅ VarroaDataset gt.csv: 라벨 0/1/3, 감염 3,947, 응애 박스 4,628.
- ✅ 71667 Sample xyxy: §5.2 + 감염 벌 `state=정상` 56/56 + 연속 촬영 간격 중앙값 4초.
- ✅ 코드: 캡처 720p, 업로드 1920 축소, AI 1024 축소, API `risk_score` null → failed, `max_det` 기본 300(문서).
- 🟡 이미지↔워시 검증 논문 0편; 육아기 응애 ~2/3 봉개 유충방; n≥300에서 3% 구분; RDA 방제 창·월동 전 10%·가루설탕법; BeeSion 97.8%(고정 리그).

## 13. 결정 로그

| 날짜 | 결정 | 근거 |
|---|---|---|
| 2026-09-25 | **스펙 v2.2 (v0.2.0 결과 반영)**: ① **τ 정책** = cal-A Youden 최대점(TPR − FPR), cal-A FPR ≤ 10% 상한(`tau_policy: youden`, `fpr_cap: 0.10`; `vdi.yaml`에 τ·정책·상한·cal-A FPR@τ 기록). Platt는 cal-A, TPR/FPR은 cal-B, 보정 조건 `TPR − FPR ≥ 0.5` 불변. 근거: (a) 2026-09-25 실측 — 같은 τ에서 cal-B FPR이 cal-A FPR보다 3~10× 낮음(colony shift) → FPR-1% 규칙이 과보수·colony 민감(v2 cal-B TPR 0.27, E1 0.05); (b) Youden은 스펙 자체의 보정 조건과 같은 양; (c) E3는 FPR-1%로 Δ0.518(여유 없음) 통과, Youden으로 Δ0.635(golden recall 0.40 → 0.57). ② **크기 베이스라인 AUROC 게이트 → 진단(보고만)** — 라벨(GT 박스 크기)의 성질이지 모델 성질이 아님(증강 무관 golden 0.79 / EV2 0.85); native 크기 3분위별 recall@τ 보고 추가(임계값 없음); recall·specificity 게이트는 유지. ③ **cal 다양성**: 다음 데이터 확장부터 cal-A·cal-B 각 ≥ 3 colony(현재 각 2, 재동결 없음 — Training 단계 동결이 최종). ④ **Stage-2 백본** = ResNet-18, 320px, cal-A AUROC 모델 선택(ShuffleNet-V2 x1.0 @224는 변형 3종 cal-B TPR ≤ 0.27로 실패, 폴백으로 유지); 서빙 CPU ≈15 ms/크롭, ONNX 출력 불변(`featmap` 512ch), CAM `fc_weight` 길이는 `metadata.json`에서 | 사용자 승인(옵션 A), 나머지 결정은 컨트롤러 위임 |
| 2026-09-22 | 목표 = 실제 벌 개체별 감염 판정 시연; 벌 크롭 → 분류; 핸드헬드 폰; 비영리; 게이트 제거; `vdi`·tier 이름 변경; 외부 데이터 혼합; Training 셋 1차; Stage-1 성충 1-class | 사용자 + xyxy 재계산 |
| 2026-09-23 | **스펙 v2.1 승인(ACCEPTED)** — 구현 계획 2개(데이터·학습 / 서빙·앱 동기)로 진행 | 사용자 |
| 2026-09-23 | **v2.1 (2차 검증)**: `risk_score`는 `score_mapping(vdi)` 점수 단위 유지; 트렌드 시리즈 분리; `bee_infested` 저장·읽기 시 집계; `vdi_display` 단일 반올림·tier 기준; CI는 raw Jeffreys 후 보정 사상(점추정만 clip); cal-A/cal-B 반분; out-of-fold 크롭; 합성 의사-프레임 부트스트랩; CAM 닫힌 형식; 타임아웃 체인 95/90s; sharp q95·HEIC·GPS strip; AI 축소 우회는 two-stage만; golden colony 합집합 동결; Gate 0(b)를 5.5단계로; 디스크 예산표; 연산 2~4일/3~8h; A3 예외; OpenAI shim 계약·폴백 규칙; insufficient→info | critic-v2 |
| 2026-09-23 | **적대적 검증 반영 v2**: 모바일 캡처·업로드 범위 포함; `insufficient` tier(0마리·품질 실패); **시각 증거 포함**(Grad-CAM++ 표시 전용 + 크롭 갤러리); DWV 제외; Stage-1 2.5만 상한 + 71488 필수; N장 합산은 읽기 시 집계; D: 파티션; Rogan–Gladen 보정 + specificity 게이트 + cal split 복원; 예측 박스 크롭; golden colony 홀드아웃; 이중 출력 이행 순서; OpenAI shim; 인용 2건 정정 | 검증 기록 문서 |

## 14. 미해결
- Gate 0 결과에 따른 촬영 가이드 하한(px/mm) — 측정 후 확정.
- 소스 혼합 비율 — 소스별 분리 지표로 결정, §13 기록.
- 학교망 다운로드 시간 — 1b 실측.
- `elevated` 모바일 화면 문안 — 소비자 이전(10단계) PR에서.
- 71488 실제 용량·서브셋 zip 단위 — AI Hub 페이지 확인 후 §5.3 표 갱신.
- Gate 0(a) 사진 5장 확보 경로(A3 예외) — 소유자.
