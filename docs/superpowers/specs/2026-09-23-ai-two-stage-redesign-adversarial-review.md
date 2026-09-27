# 적대적 검증 — 2-stage 재설계 스펙 v1 (2026-09-23)

> 대상: `2026-09-22-ai-two-stage-redesign-design.md` (DRAFT)
> 방식: 관점별 비판자 4명(ML/데이터 · 지표/통계 · 실행 가능성 · 근거/모순, 각 Opus) → 리드가 Sample 330장·코드·논문 원문으로 재검증
> **판정: 현재 스펙은 승인 불가. 차단 7건, 주요 10건. v2로 개정 후 재검토.**

## A. 차단 (BLOCKER) — 재검증 완료

| # | 결함 | 검증 근거 | 수정 방향 |
|---|---|---|---|
| B1 | **해상도 체인이 3곳에서 끊김.** 캡처 `ResolutionPreset.high`(=720p) → 업로드 전 긴 변 1920 축소(q85) → API sharp 재인코딩 → AI `MAX_EDGE=1024`. 스펙 §4 "원본 보존"은 AI만 고쳐선 성립 안 함 | `capture_screen.dart:83`, `capture_preprocess.dart:22-24`, `preprocess.py:30`, `s3-client.ts:75` | 모바일 캡처 `max` + 1920 캡 제거 + AI 축소 우회를 **범위에 포함**. 실제 업로드 이미지의 벌 px 실측을 Gate 0에 포함 |
| B2 | **감염 벌에 형태 단서가 없다.** 71667 `성충_응애` 56/56이 `state=정상`. 분류기가 볼 수 있는 건 응애 자체뿐 → 폰 해상도로 축소하면 양성이 라벨 노이즈가 됨. 스펙 §0의 Bilik "몸 변형" 논리는 우리 데이터에 부적용 | Sample 메타 전수 | **Gate 0**: 원본 크롭으로 학습 후 px/mm(22→15→12→9)별 recall 곡선 측정. 붕괴 지점 이상을 촬영 가이드(반 소비판·근접)로 강제하고 축소 증강 하한을 거기에 맞춤. DINOv2 프로브를 Phase 2에서 Gate 0로 이동 |
| B3 | **Stage-2 게이트가 거짓 양성을 제한 못 함.** "정상 precision ≥0.90"은 유병률 4.5%에서 specificity 0.04짜리도 통과. FPR 3%면 건강한 벌통이 VDI 3% = `elevated` | 산술 | specificity ≥ 0.985 게이트 + 폰 도메인 음성 FPR 보고 + "0% 감염 golden → VDI<3 in ≥95%" e2e 테스트 |
| B4 | **τ 미정의 + temperature scaling은 판정을 못 바꿈.** σ(z/T)는 z=0에서 항상 0.5 → VDI 불변. 가중 CE + 1:3 오버샘플은 이중 보정 | 수식 | τ를 `vdi.yaml`에 명시(cal split에서 목표 FPR로 결정), 가중 CE **또는** 오버샘플 하나만, VDI_adj = (VDI−FPR)/(TPR−FPR) 병기. 구 설계의 15% cal split 복원 |
| B5 | **golden이 colony-disjoint가 아니고 근접 중복 누수.** `per_colony_time_block`은 모든 colony를 양쪽에 넣는 설계. 연속 촬영 간격 중앙값 4초, 317쌍 중 292쌍 ≤10분. `has_varroa_label()`은 YOLO class 1을 세므로 1-class에서 golden 추출 불가 | `split_strategy.py:135`, `golden_holdout.py:35`, Sample 타임스탬프 | golden = colony × 날짜 블록 단위 홀드아웃, 선택은 원본 JSON `category_id==5`로, colony·device당 ≥10분 디듀프. Stage-1/2 공유 split을 manifest 하나로 강제 + 테스트 |
| B6 | **`risk.py` 삭제가 OpenAI 폴백·부스 앱을 깨뜨림.** A5 "OpenAI 경로 변경 없음"과 §8 모순. 부스 앱 18파일이 `riskScore/tier` 소비, 스펙에 누락 | `orchestrator.py:17,67-78`, `make_booth_cases.py:22,114`, 참조 파일 수 | `risk.py/risk.yaml`를 OpenAI·부스용으로 동결(shim)하거나 OpenAI를 범위에 넣어 새 계약으로 매핑. 폴백 트리거 재정의. 부스 범위 명시 |
| B7 | **스키마 순서가 프로덕션을 깨뜨림.** API가 `risk_score===null`이면 `failed` 저장·쿼터 환불(`analyses.ts:141`), tier 매핑 `safe/watch/danger` 키(`:80-81`), 트렌드 `avg(varroaInfectionRisk)`. AI(8단계)를 API(9단계)보다 먼저 배포하면 전 분석이 실패 | 코드 | 순서 역전: ① API/DB 관용(양 계약 수용, failed는 `engine_used` 기준) → ② AI 이중 출력(`risk_score := round(vdi)`) → ③ 소비자 이전 → ④ 구 필드 제거. `ai_models` v0.2.0 row + stage 버전은 `raw_response`에 |

## B. 주요 (MAJOR)

| # | 결함 | 수정 방향 |
|---|---|---|
| M1 | **박스 기하 지름길.** 긴 변 중앙값 정상 325 / 응애 413 / 날개불구 636px, 응애 하위 10%(338) > 정상 중앙값. 응애 31/56이 이웃 벌과 겹침. GT 박스 크롭 = "느슨한 박스 = 감염" 학습, 서빙은 타이트한 검출 박스 | Stage-2 크롭을 **Stage-1 예측 박스(IoU≥0.5 매칭)**로 생성. 크기·종횡비만으로 로지스틱 베이스라인 AUROC 보고(>0.7이면 지름길 살아있음) |
| M2 | **e2e golden 지표 퇴화.** 성충 0마리 139/330장, 성충 있는 이미지 중앙값 4마리(최대 28). VDI 2~12% 구간 15장. tier 일치율은 "감염 벌 하나라도 있나"로 환원, 전부 `low` 베이스라인 ~0.7 | 같은 colony·세션 이미지를 합쳐 ≥300 성충 의사-프레임 구성, 진짜 VDI로 층화. 사소 베이스라인과 tier 혼동행렬 필수 보고. "폰 도메인 정확도는 미측정"을 명시 |
| M3 | **Stage-1 스케일 갭 ~5×, SAHI 트리거 도달 불가.** 학습 벌 ~175px@1280 vs 서빙 ~32px; `max_det` 기본 300이라 ">400" 불가 | `max_det ≥1500`, ≥8MP면 항상 타일, scale 증강 0.15까지, 71488을 **필수**로 승격, 밀집 폰 프레임 recall 보고 |
| M4 | **도메인·기기·colony가 라벨을 예측.** 소문촬영기 11/11 감염, colony 007/006/008/015/002는 100% 감염 이미지, 001은 8%. VarroaDataset(29%)·EV2(62%) prior 상이 | 소스·기기·colony별 지표 분리 보고, 소스별 양성 prior 균등 샘플링, 임베딩→소스 선형 프로브, leave-one-device-out |
| M5 | **음성 라벨 노이즈.** 감염 이미지 53장 중 50장이 응애 정확히 1개(대표 1개 표기 습관 의심). 같은 이미지의 정상 347개는 미검증. 날개불구(DWV)를 음성으로 두는 건 §0 논리와 충돌 | 감염 이미지 내 정상 크롭 100개 육안 감사, 학습 음성에서 제외/감량. DWV는 Stage-2 학습·평가에서 **제외**(양성도 음성도 아님) |
| M6 | **CI가 표본 오차만 표현.** 분류기 오차·같은 소비판 내 상관·봉개 유충방 미관측 무시. n=300에서 3%·10% 경계가 구간 안에 들어와도 단일 tier 표시 | 필드명 `sampling_ci95`, tier를 CI로 유도(상한<3 → low, 하한≥10 → high, 나머지 elevated/uncertain) |
| M7 | **최악 시연 케이스 미정의.** 0마리 → 0/0; 1마리 감염 → 100% `high`; 전부 플래그(블러) → `high`; 품질 경고가 tier와 무관 | `bee_total=0` → `vdi:null, tier:insufficient`(테스트), 심한 블러 → `insufficient`, 박스는 항상 표시. (게이트 아님 — 표시는 유지) |
| M8 | **디스크 예산 초과.** 206GB 분할 zip은 부분 해제 불가. 병합+해제 412~618GB > 411GB. 변환·split·golden 전부 `shutil.copy2` | 2차 드라이브 또는 서브셋. 변환/split을 복사 대신 manifest(txt 이미지 목록)로. NTFS symlink는 개발자 모드 |
| M9 | **Stage-1 연산 과소평가.** 312k×100ep@1280 ≈ 4060에서 수 주. batch 8@1280은 8GB 초과 가능 | Stage-1 데이터 2~3만 장 상한, imgsz 1024 또는 타일@640, `batch:-1` |
| M10 | **윈도우 네이티브 툴체인.** `read_text()` 인코딩 미지정 6곳 + `yolo.yaml` 한글 31줄 → cp949 크래시. `make`·`trash` 없음. 한글 경로 압축해제 깨짐 위험. `workers:8` WinError 1455 | `PYTHONUTF8=1` + `encoding="utf-8"` 전면, make 타깃의 PowerShell/`tasks.py` 등가물, 7-Zip UTF-8, workers 4 |
| M11 | **사진 N장 합산이 DB 계약과 충돌.** `UNIQUE(image_id, model_id)` + 단일 `imageId` | N장 합산은 클라이언트 측 집계 또는 별도 `analysis_sessions` 테이블 — 결정 필요 |
| M12 | **인용 오류.** "종횡비 보존 우세" → 실제 **p=0.376 유의차 없음**; "28×28은 입력과 무관" → 실제 **응애 10~20px@224 조건**; ShuffleNet 안정성은 "응애가 명확히 보이는 이미지만" 큐레이션한 셋의 전처리 민감도. "Liu/Bilik 2023"은 Liu et al., 입구 카메라 | §4·§12 문장 정정, "인디스트리뷰션·가시응애 결과"로 한정 |
| M13 | **단일 스테이지 대안 미반박.** xyxy 수정 + 성충 2-class + 1280 타일 단일 YOLO도 같은 출력. 2-stage의 실제 근거(외부 크롭 데이터 활용, 원본 해상도 크롭)가 미기술 | 수정된 단일 스테이지를 **e2e 베이스라인**으로 추가, 데이터 가용성 논거 명시 |
| M14 | **시연에 시각적 증거 없음.** 빨간 박스 + 퍼센트뿐, 왜 빨간지 안 보임. FPR>0이면 건강한 프레임에 근거 없는 빨간 박스 | 표시 전용 Grad-CAM++ 또는 top-k 크롭 확대 갤러리 — **사용자 결정 필요**(히트맵 제외 결정과 충돌) |
| M15 | **CPU 서빙 리스크.** beta ai `mem_limit 1536m`, 800크롭 배치 텐서 482MB, t3 크레딧 소진 시 5× 느려져 30s 타임아웃 → failed | Stage-2 64개씩 청크, 소프트 크롭 상한 + 랜덤 샘플 기록, 시연은 T3 Unlimited/c-class, 타임아웃 상향 |
| M16 | **크리티컬 패스 미기술.** Stage-2는 Validation 셋(26GB)+VarroaDataset+EV2로 즉시 시작 가능한데 206GB에 묶여 있음 | 1단계 병렬, 2·3·5를 Validation+외부로 먼저 |

## C. 기각된 반론
- "`성충_응애` 박스가 여러 벌을 묶은 영역" — 다른 성충을 50% 이상 포함하는 박스 2/56, 정상과 IoU>0.3 0건 → 벌 한 마리 단위 맞음(느슨할 뿐). Q3=B·벌 단위 설계 유지.

## D. 구현 전 미결 (스펙 v2에 답해야 함)
τ 규칙 · `bee_total=0` 동작 · 품질 체크 임계값 · 서빙 시 <48px 크롭 처리 · 혼합 비율 선택 지표 · 성충 전용 golden 재정의 · 새 tier → `overall_health`/severity 매핑 · 모바일 `elevated` 화면 · 71488 필수 여부 · 히트맵/크롭 갤러리 · N장 합산 저장 구조 · 디스크(2차 드라이브 vs 서브셋)

## E. 출처
비판자 원문: 세션 스크래치 `review/critic-{ml,metrics,exec,claims}.md` (Sample 통계·코드 라인·산술 포함). 리드 재검증: Sample 330 JSON(xyxy), `.playwright-mcp/agronomy2026.txt`, 각 코드 파일 라인.
