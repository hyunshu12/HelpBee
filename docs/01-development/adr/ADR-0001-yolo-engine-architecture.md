# ADR-0001 — HelpBee 자체 YOLO 엔진 아키텍처 (단일 스테이지 v0.1.0 → 2-stage v0.2.0)

> Status: **ACCEPTED** (2026-06-05)
> Decision owner: AI팀 lead
> Supersedes/relates: `docs/superpowers/specs/2026-05-07-yolo-two-stage-design.md` (v0.2.0 설계로 재범위)
> 검증 출처: 16-에이전트 적대적 검증 워크플로 (재근거화 4 · 주장검증 7 · 다관점 판정 4 · 종합 1), 2026-06-05

---

## 1. 결정 (Decision)

자체 YOLO 응애 진단 엔진을 **단계적(phased)** 으로 간다.

| 단계 | 아키텍처 | 데이터 | 조건 |
|---|---|---|---|
| **v0.1.0 (지금)** | **단일 스테이지 3-class 검출** (`bee_normal` / `bee_with_varroa` / `bee_other_disease`) | AI Hub 71667 단독 | config/eval 사소 교정 후 즉시 학습·게이트된 dual-engine 베이스라인으로 배포 |
| **v0.2.0 (이후)** | **2-stage** 벌 검출 → 마리별 감염 분류 (승인 설계 `2026-05-07-yolo-two-stage-design.md`) | 71488 + Zenodo VarroaDataset + 71667 crop | **라이선스 게이트(71488 상용·내국인, Zenodo CC BY) 통과 시에만** 착수 |

확신도 **76/100**.

핵심 원칙: **YOLO는 출시 차단요소가 아니다.** OpenAI Vision이 MVP의 상시(always-on) 사용자 엔진이고, YOLO는 `5% canary → green이면 100%`로 점진 이관되는 비용·주권·정확도 연구 트랙이다. 따라서 단일 스테이지를 먼저 내보내도 **사용자에게 가는 정확도 리스크가 0**이며, 2-stage는 그 위에서 정확도 천장을 올리는 후속 베팅으로 남는다.

---

## 2. 맥락 (Context)

작업 시작 시점에 AI 도메인에는 **서로 다른 두 설계가 공존**하고 있었다.

- **실제 학습 코드 (committed)** — 단일 스테이지 3-class 검출. `training/configs/yolo.yaml`(YOLOv11s **+ P2 head**, imgsz **1280**), `dataset.yaml`(nc:3), `risk.yaml`(`infestation_rate`), `aihub_to_yolo.py`(71667 7→3 매핑), `train.py`/`eval.py`/`split_strategy.py`/`golden_holdout.py`, Makefile. **전부 동작 가능 상태, 데이터 1개(71667)**.
- **승인된 설계 문서 (`2026-05-07`, "APPROVED")** — 2-stage 검출→분류. Stage1 YOLOv11s@640(P2 미사용, 71488), Stage2 binary 분류기@224(Zenodo + 71667 crop), `infected_bee_rate`, INT8 필수. **코드 0줄 — repo 전역 grep(`71488`/`zenodo`/`stage2`/`aihub_to_stage2`/`bee_detector`/`infested_clf`) 결과 0건.** 605줄 pseudocode만 존재.

추론 서버(`apps/ai/app/`)는 `/health`만 있고 `/analyze` 계열·services·schemas 전부 `.gitkeep`(미구현).

어느 것이 진실의 원천인지 정해져야 다음 작업을 시작할 수 있어, 이 ADR로 확정한다.

---

## 3. 근거 (Rationale)

판정 패널 4관점 점수 (0–10):

| 관점 | 승자 | 단일 | 2-stage |
|---|---|---|---|
| 출시속도 · 1인 운영 | **단일** | 8 | 4 |
| 정확도 천장 · 전략 목적 | 2-stage | 5 | 7 |
| 데이터·라벨 적합·라이선스·도메인시프트·PII | 2-stage | 5 | 7 |
| 유지보수·가역성·매몰비용 | 2-stage | 5 | 7 |

3관점이 2-stage를 가리키지만, **YOLO가 출시 비차단**이라는 확정 사실 때문에 "지금 둘 중 하나"가 아니라 **단계적**이 정답이 된다.

1. **구현 현실이 '가장 빠름'을 결정한다.** 단일 스테이지는 오늘 학습 가능(코드+데이터 완비), 2-stage는 crop 추출기·2개 학습 파이프라인·3-way colony-disjoint 분할·INT8 parity·stage별 canary를 **전부 새로 작성**해야 한다.
2. **YOLO 정확도는 출시 차단요소가 아니다 [CONFIRMED/high].** `apps/ai/CLAUDE.md §1`이 OpenAI를 "상시" 사용자 엔진으로, 모든 YOLO 롤아웃을 "if green" 게이트로 규정. 실패한 YOLO는 0–5% canary에 머물고 OpenAI가 계속 서빙.
3. **1인 운영 + over-engineering 금지(`infra/CLAUDE.md` "복잡도 < 운영 가능성")가 지금은 단일을 지지** [CONFIRMED/medium]. 2-stage는 오류 곱셈(0.85×0.91≈0.77 e2e recall, 설계 자체의 #1 리스크)·독립 버전 2모델·INT8 필수·τ 보정 의식·3 데이터소스를 솔로 메인테이너에게 상시 부담시킨다.
4. **2-stage가 진짜로 정확도 천장이 높다(전략 목적 = OpenAI를 결국 능가).** 단일 스테이지는 71667의 희소 응애 2.4%(100/4,210)로만 감염 신호를 학습하고 copy_paste 0.3은 같은 ~100개를 복제할 뿐. 2-stage는 외부 균형 분류 코퍼스 + Lee et al. 91% 선례를 흡수하고, 71667의 "감염 벌 영역" 라벨이 Stage2 crop에 완벽 적합 [Q3=B CONFIRMED]. → 그래서 단일 영구화가 아니라 **단계적**.
5. **단계적이 가장 가역적·최저후회.** 승인 설계 자체가 "single-stage 재통합"을 v0.2.0 실험으로 명시(line 584). 공유 데이터 계층(`split_strategy.py` per_colony_time_block, 71667 변환, golden 300)이 양쪽에 그대로 전이. 71488 라이선스 실패 시 설계의 폴백이 문자 그대로 "71667 detection-only" = **출시한 단일 스테이지** → 재작업 0.

---

## 4. 검증된 주장 (Verified Claims)

7개 핵심 주장을 적대적으로 검증한 결과:

| # | 주장 | 판정 | 비고 |
|---|---|---|---|
| 1 | Q3=B 라벨이 2-stage에 적합·단일에 불리 | **partial** | "2-stage 적합"은 확정. "단일 불리"는 과장 — 라벨 특성은 검출을 **쉽게** 함(박스 medium~large). 불리한 건 검출이 아니라 imbalance이고 그건 양쪽 공통 |
| 2 | yolo.yaml P2+1280이 AIHUB §6과 모순·과설계 | **partial** | 모순은 verbatim 확정. "4× 느림"은 imgsz 1280 요인(640 대비)이며 P2 요인(≈10–15%)과 혼동. 결정엔 저영향 |
| 3 | OpenAI=상시 엔진, YOLO 정확도=비차단 | **CONFIRMED/high** | 모든 근거가 문서에 명시. 결정의 주춧돌 |
| 4 | 단일은 OpenAI 못 이기고 2-stage는 가능 | **partial** | 방향은 옳으나 "Zenodo 13.5k 균형"은 **사실 오류**(1:2.4 불균형), "OpenAI 능가"는 양쪽 미벤치마크 |
| 5 | 2-stage 3개 데이터 모두 실재·라이선스 OK | **partial** | 실재는 확정. **라이선스는 71488·71667 미확정**(상용·내국인), Zenodo만 CC BY(그조차 W1 TODO) |
| 6 | eval.py VMIR 분모 버그 | **CONFIRMED/low** | `varroa/normal*100`, class 2 누락. risk.yaml/AIHUB §10은 전체 벌 분모. 아키텍처 무관 |
| 7 | 2-stage 운영비용(곱셈·2모델·INT8·3소스) 더 큼 | **CONFIRMED/medium** | 4항 모두 설계 문서에 명시. 솔로 팀에 상시 부담 |

### 정정된 사실 (이전 분석 오류)
- **"Zenodo 13.5k 균형" → 틀림.** 공개 Zenodo VarroaDataset(DOI 10.5281/zenodo.4085044, CC BY 4.0)은 **3,947 감염 : 9,562 정상 = 1:2.4 불균형**. 승인 설계의 "10k balanced"는 Lee et al.의 **비공개** 균형 셋을 혼동.
- **"YOLO가 OpenAI를 능가" — 양쪽 다 벤치마크 없음.** repo에 OpenAI 정확도 baseline 부재. 베타 1주차 200+ 실사진 dual-engine confusion matrix로 실측 필요.

---

## 5. 결과 (Consequences)

**긍정**
- 6월 MVP 창에 YOLO 트랙을 현실적으로 태움(또는 비차단으로 안전히 지연).
- 단일 스테이지가 2-stage의 공식 폴백이 되어 라이선스 리스크를 흡수.
- 공유 데이터 계층이 양 단계에 재사용 → 매몰비용 최소.

**부정 / 비용**
- **이행 부채**: 곧 대체할 v0.1.0 config/eval를 지금 고쳐서 배포(이중 비용).
- **단일 영구화 리스크 (가장 강한 반론)**: 솔로 팀이 동작하는 비차단 v0.1.0을 내보내면 더 어려운 2-stage를 영영 안 만들 강제력이 약하다 → phased가 조용히 "단일 영구"로 붕괴할 수 있다. **완화: v0.2.0 라이선스 게이트(remediation step 7)에 하드 오너 + EOW 데드라인을 부여**해야 이 반론을 이긴다. 그게 없으면 반론이 옳다.

---

## 6. 재사용 / 변경 / 보존 (Code Disposition)

**그대로 살아남는 자산 (아키텍처 무관)**
- `training/data/split_strategy.py` — per_colony_time_block. 최고가치, 양 단계 공유(2→3-way 확장만).
- `training/data/aihub_to_yolo.py` — JSON 파서·`_resolve_image_path`·`CLASS_MAPPING`·메타 추출 → Stage2 crop 추출기의 라이브러리로 재사용.
- `training/data/golden_holdout.py` — 다양성 강제 holdout + golden 300 = `golden-71667` 슬라이스(설계 §4.5).
- `training/train.py` — 범용 Ultralytics resume/pretrained 래퍼 → Stage1에 그대로, Stage2-cls에 거의.
- `training/configs/dataset.yaml`(nc:3), `risk.yaml`(전체-벌 분모 — 정본), `AIHUB_71667.md`.

**변경/강등할 것** → §7 remediation 참조.

---

## 7. 이행 계획 (Remediation Plan)

> 이 ADR 채택 직후의 작업. ✅ = 본 PR에서 이미 반영, ⏳ = 후속(오너 승인 필요).

| # | 작업 | 파일 | 위험 | 상태 |
|---|---|---|---|---|
| 1 | 이 ADR 작성·결정 기록 | `docs/01-development/adr/ADR-0001-*.md` | low | ✅ |
| 2 | config 린화: imgsz 1280→640, model을 stock yolo11s로(P2 드롭), 거짓 "작은 객체" 근거 주석 교정 | `training/configs/yolo.yaml` | low | ✅ |
| 3 | P2 변형을 v0.2.0 실험으로 강등 + 근거 교정 주석(AIHUB §6 인용) | `training/configs/yolov11s-p2.yaml` | low | ✅ |
| 4 | 2-stage 설계 헤더를 v0.1.0 → **v0.2.0 목표**로 재범위 + ADR 링크 | `docs/superpowers/specs/2026-05-07-*.md` | low | ✅ |
| 5 | §8 드리프트 정렬 + ADR 포인터(yolov8s/640 → yolov11s/640, golden 300) | `apps/ai/CLAUDE.md` | low | ✅ |
| 6 | datasets README 정렬(오타 `yamlㅌ1`, nc:1→3, golden 100→300, 71667 주데이터 명시) | `apps/ai/training/datasets/README.md` | low | ✅ |
| 7 | **eval.py 버그 수정**: 분모를 전체 벌(normal+varroa+other_disease)로, class 2 포함, `varroa_recall` 조회명 `varroa_mite`→`bee_with_varroa`, 'VMIR'→`infestation_rate` 개명, 단위 테스트 추가 | `training/eval.py`, `app/tests/unit/` | medium | ⏳ |
| 8 | golden data.yaml 출력 nc:2→nc:3, Makefile eval이 `NAME` 추적 | `training/data/golden_holdout.py`, `Makefile` | low | ⏳ |
| 9 | 단일 v0.1.0 end-to-end 실행(convert→golden→split→train→eval) → golden mAP/recall/`infestation_rate` MAE 베이스라인 JSON 커밋 | `training/*` | medium | ⏳ |
| 10 | v0.1.0 가중치를 게이트 dual-engine에 연결(/analyze=OpenAI, /analyze/yolo·dual=admin, YOLO 0–5% canary 유지) | `apps/ai/app/*`, `apps/api/src/services/ai-client.ts` | medium | ⏳ |
| 11 | **v0.2.0 라이선스 게이트 (하드 오너 + EOW)**: 71488 상용·내국인 가부, Zenodo CC BY 확인. 실패 시 폴백=출시한 단일. 통과 후에만 crop 추출기·Stage2 학습·τ 보정·INT8 착수 | spec, `training/data/` | high | ⏳ |

---

## 8. 미해결 질문 (Open Questions) — 오너 결정 필요

1. **[W1 게이트, 오너=AI lead] 71488이 상용 양봉 진단 SaaS에 사용 가능한가, 내국인/비상용 전용인가?** 이 한 답이 v0.2.0 2-stage의 빌드 가능 여부를 결정. **71667 자체도 동일한 상용+내국인 제약** → 출시할 단일 스테이지에도 해당하므로 아키텍처 무관하게 법무 확인 필요.
2. 공개 Zenodo(CC BY, **1:2.4 불균형** — 설계가 가정한 "balanced" 아님)로 Stage2 Phase1 충분한가, 아니면 Lee et al. 비공개 균형 10k 접근 필요한가?
3. **OpenAI Vision의 이 태스크 실제 정확도는?** 어떤 파일도 벤치마크하지 않음. "YOLO가 결국 OpenAI 능가" 목표가 양쪽 미검증 → 베타 dual-engine confusion matrix 필요.
4. 단일 v0.1.0이 golden holdout에서 실제로 내는 `infestation_rate` 정확도는? (step 9의 eval JSON이 v0.2.0 투자 정당화 판단 데이터)
5. golden holdout이 내부적으로 약함(`golden_holdout.py`도 "같은 데이터셋 내부 분리 → 일반화 평가 약함" 인정)을 팀이 수용하는가? 진짜 일반화는 외부 베타 사진 확보 후 — 모든 YOLO 아키텍처가 >5% canary로 신뢰받는 시점에 영향.

---

## 9. 고려한 대안 (Alternatives Considered)

- **순수 2-stage 즉시 전환** — 2/3 판정 관점이 지지하고 설계가 이미 승인·14건 사전리뷰 보강됨. 그러나 6월 인접 일정을 **미확정 상용 라이선스(71488)** 에 베팅 + 코드 0줄. 단계적이 이 반론을 이기려면 step 11 게이트에 하드 데드라인 필수.
- **순수 단일 스테이지 영구** — 가장 단순하나 YOLO의 존재 이유(OpenAI 정확도+비용 능가)인 정확도 천장을 포기. 2.4% 응애 + colony001 75% 지배로 천장이 낮음.

---

## 10. 참조 (References)

- 2-stage 설계 (= v0.2.0): `docs/superpowers/specs/2026-05-07-yolo-two-stage-design.md`
- 데이터셋 진실 소스: `apps/ai/training/datasets/AIHUB_71667.md` (특히 §6 Q3=B, §7 통계, §10 위험도 정의)
- AI 도메인 가이드: `apps/ai/CLAUDE.md`
- 운영 제약: `infra/CLAUDE.md` ("복잡도 < 운영 가능성")
- 외부: Zenodo VarroaDataset DOI 10.5281/zenodo.4085044 (CC BY 4.0); AI Hub 71488 "지능형 양봉 데이터"; Lee et al., *A YOLOv8-Based Two-Stage Framework...*, JKSCI 2024.10 (det mAP@0.5 0.701 / cls 91%)
