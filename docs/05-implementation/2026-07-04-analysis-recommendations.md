# 2026-07-04 — 분석 권장 조치(recommendations) 파이프라인 end-to-end

> PR: #36 (예정) · 브랜치: feature/analysis-recommendations → develop · 머지일: (예정)

## 범위 (Scope)

"사진 → 응애 진단 → **처방/주의(recommendations)**" 의 마지막 구간을 연결했다. AI가 tier
기반 한국어 권장 조치를 생성(기존)하고, 백엔드가 **응답으로 반환**(신규)하며, 모바일 레포트
화면이 **백엔드 권장 조치를 severity 색과 함께 렌더**(신규)한다. 이전에는 DB 저장만 되고 어떤
분석 응답에도 포함되지 않아 결과 화면이 클라이언트 하드코딩 문구에 의존했다.

## 산출물 (Deliverables)

### apps/ai (권장 조치 생성 — enum 소스는 risk.yaml)
- `training/configs/risk.yaml` — `recommendations.no_count_caveat` 추가(응애 개체 카운트
  불가 시 데이터 정직성 안내).
- `app/services/risk.py` — `recommendations_for(..., count_available=)` 파라미터 추가.
  `estimated_count is None`(YOLO)일 때 자리가 남으면(≤5) caveat append, tier 문구는 절대
  잘리지 않음. `compute_risk`가 `count_available` 전달.
- `app/services/orchestrator.py` — OpenAI 폴백 경로도 `count_available=False`로 정합.
- `app/tests/unit/test_risk.py` — caveat append/비잘림 회귀 2건.

### packages/database (읽기 헬퍼)
- `src/queries/analyses.ts` — `listRecommendationsByAnalysisIds(db, ids[])` →
  `Map<analysisId, {order,content,severity}[]>` (order 오름차순). `AnalysisRecommendation`
  타입 export. (insert는 기존 `createSingleAnalysis`가 트랜잭션 내 인라인 처리 — 중복 방지 위해
  별도 insert 헬퍼는 추가하지 않음.)

### apps/api (영속 + 반환)
- `src/routes/analyses.ts` — `AnalysesDeps.getRecommendations` 추가. `withRecs()`로 분석 row에
  `recommendations` 배열을 실어 반환: **POST**(신규 201·멱등 200·실패 200[])·**GET /:id**.
  목록 `GET /`는 미포함(페이로드).
- `src/app.ts` — `getRecommendations` 와이어링(`listRecommendationsByAnalysisIds`).
- `src/routes/analyses.test.ts` — POST 성공/실패/멱등 recommendations, GET :id join 검증.

### apps/mobile (레포트 화면)
- `lib/features/analyses/data/analysis_dto.dart` — `RecommendationDto{order,content,severity}` +
  `Analysis.recommendations`(기본 빈 배열, 하위호환). `fromJson`이 malformed/빈 content 항목 제거.
- `lib/features/analyses/presentation/report_screen.dart` — 백엔드 recommendations 우선 렌더
  (severity별 번호 배지 색 = tier 토큰), 없으면 클라이언트 tier 문구로 폴백(목록 유입 행 대비).
- `test/analysis_dto_test.dart` — recommendations 파싱 3건.

### docs
- `docs/01-development/frontend-api-integration.md` §4 — GAP 경고 → 실제 계약(POST·GET :id 포함,
  목록 미포함, severity 매핑, 실패 빈 배열). §10 Readiness 표/요약 갱신.
- `apps/ai/CLAUDE.md` §4 — risk.py=recommendations enum 소스 표기.

## 검증 (Verification)

- `pnpm --filter @helpbee/api test` — **167 passed** (신규 3건 포함).
- `pnpm --filter @helpbee/api type-check` / `pnpm --filter @helpbee/database type-check` — clean.
- `cd apps/ai && pytest -q` — **67 passed**.
- `cd apps/mobile && dart analyze` — **0 issues**. (flutter test는 이 Mac Xcode 라이선스
  이슈로 미실행 — DTO 파싱 테스트만 추가, 다음 실행 가능 환경에서 확인.)
- 라이브 E2E(로컬 API:3001 + AI:8000): presign→S3 PUT→confirm→POST /analyses 응답에 한국어
  `recommendations[]` 존재, GET /:id 동일 확인.

## 후속 작업 (Follow-up)

- 어드민 진단 상세(dual)에도 recommendations 노출 검토(현재 사용자 흐름만).
- 베타 실측 VMIR 확보 후 recommendations 문구/임계 보정(risk.yaml).
- flutter test 실행 가능 환경에서 DTO/위젯 테스트 재확인.

## 참조

- AI 권위 가이드: `apps/ai/CLAUDE.md` §8-8(recommendations enum화), 데이터: `training/datasets/AIHUB_71667.md`(Q3=B)
- API 권위 가이드: `apps/api/CLAUDE.md`, DB: `packages/database/CLAUDE.md`
- 계약: `docs/01-development/frontend-api-integration.md` §4
