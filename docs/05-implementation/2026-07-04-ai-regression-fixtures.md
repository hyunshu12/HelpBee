# 2026-07-04 — AI 회귀 fixture 게이트 (P1-3)

> PR: #39 (예정) · 브랜치: feature/ai-regression-fixtures → develop · 머지일: (예정)

## 범위 (Scope)

`apps/ai/CLAUDE.md` §10-2 가 요구하지만 실체가 없던 **회귀 게이트**를 구축한다. 서빙 경로
(`run_analysis(engine="yolo")` = preprocess→YOLO(ONNX)→risk) 스냅샷을 매니페스트로 박제해,
프롬프트/모델핀/`risk.yaml` 변경이 출력을 흔들면 잡는다. 이전엔 `pytest -m regression` 이 0건이었고
`app/tests/fixtures/` 가 비어 있었다(PR #36 risk.yaml 변경도 게이트 없이 머지됨).

## 산출물 (Deliverables)

- `apps/ai/training/data/make_regression_fixtures.py` — 선택 스크립트. 71667 Sample 330장에서
  클래스별 seed 고정 24장 선택(응애 8/정상 8/기타질병 8, 성충·유충 혼합) → 서빙 경로 실행 →
  매니페스트 작성. 재실행 시 fixtures 배열 byte-identical.
- `apps/ai/app/tests/fixtures/regression_manifest.json` — **유일하게 커밋되는 산출물**.
  `[{path, sha256, expected_risk_score, expected_tier, class_folder, bee_total, infestation_rate}]`
  + 메타(model_version=v0.1.0, conf=0.25, iou=0.5, imgsz=640, seed, created_at).
  경로는 `training/datasets/Sample/...`(gitignored) 상대경로.
- `apps/ai/app/tests/regression/test_regression_gate.py` — `@pytest.mark.regression`, 매니페스트
  parametrize(케이스명=class/파일명). 모델·데이터셋 부재 시 전 케이스 skip, sha256 불일치 시 그
  케이스만 경고+skip. 판정: `abs(Δrisk) <= 10` AND tier 정확 일치.
- `apps/ai/pytest.ini` — `regression` 마커 등록 + `addopts = -m "not regression"`(기본 실행 제외).
- `apps/ai/Makefile` — `test-regression`, `regression-fixtures` 타깃.
- `apps/ai/CLAUDE.md` §10-2 현행화(위치·매니페스트·라이선스·skip 규칙).

## 라이선스 제약 (핵심)

71667 원본 이미지는 **재배포 금지(내국인 제약)**. 이미지 자체는 절대 git에 넣지 않는다 —
매니페스트(경로+sha256+기대값)만 커밋. `.gitignore` 의 `training/datasets/*` 가 이미지를 커버하고,
`git status` 로 이미지 0건 스테이징 확인. 회귀 테스트는 로컬에 데이터셋+모델이 있을 때만 실제로 돈다.

## 검증 (Verification)

- `pytest -q` → **65 passed, 24 deselected** (기본 실행은 회귀 제외, 기존 단위 그대로 green).
- `pytest -q -m regression` → **24 passed** (모델+Sample 로컬 존재).
- `HOME=/tmp/emptyhome pytest -q -m regression` → **24 skipped** (모델 부재 = CI 시나리오, clean skip).
- 결정성: 선택 스크립트 재실행 → fixtures 배열 sha256 동일(created_at 만 상이).
- `git status` → 이미지/바이너리 0건 스테이징.
- fixture 분포: risk_score min/median/max = 0/21/90, tier safe 12 / watch 11 / danger 1.

### 알려진 제약

- **스냅샷 성격**: 기대값은 ground-truth 가 아니라 "현재 모델 서빙 출력". 정확도 평가가 아니라 드리프트
  감시용. v0.1.0 베이스라인은 약해 응애 폴더 사진도 varroa 0 검출이 다수(risk 0)다.
- **golden 겹침 미검증**: golden holdout(`training/datasets/golden/`)이 로컬에 없어 fixture/golden
  disjoint 를 정적 확인 못 함. fixture 는 학습에 안 쓰이므로 데이터 누수는 없으나, golden 확보 후
  disjoint 재확인 권장.
- **저개체 clamp**: bee_total<5 이미지가 다수라 low_confidence clamp(21~70)로 tier=watch 로 몰림.

## 후속 작업 (Follow-up)

- 베타 외부 데이터 확보 시 fixture 를 현장 사진으로 교체(71667 내부 분포 동질 → 일반화 평가 약함).
- YOLO 가중치 상향(v0.1.x) 후 매니페스트 재생성 + 회귀 diff 를 PR 에 첨부.
- CI 에서 데이터셋/모델 캐시를 주입해 회귀를 실제로 도는 잡 추가 검토(현재는 skip).

## 참조

- 권위 가이드: `apps/ai/CLAUDE.md` §10 (테스트), §8-8 (risk 산출)
- 서빙 skew 교훈: `docs/05-implementation/2026-06-16-yolo-inference-decode-and-preprocess-fixes.md`
- 데이터셋: `apps/ai/training/datasets/AIHUB_71667.md`
- risk 정의: `apps/ai/training/configs/risk.yaml`
