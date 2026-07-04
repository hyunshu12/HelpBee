# 2026-07-04 — 실패 분석 재시도(retry-on-failed)

> PR: #37 (예정, #36 스택) · 브랜치: feature/analysis-retry-on-failed → develop · 머지일: (예정)

## 범위 (Scope)

`analyses`에는 `UNIQUE(image_id, model_id)` 제약이 있고 `POST /v1/analyses`는 같은 이미지에
행이 있으면 그대로 반환한다. 문제는 그 행이 `status='failed'`(예: AI 서버 다운 →
`error:'ai_unavailable'`)일 때도 마찬가지라, **한 번 실패한 이미지는 영원히 재분석 불가**였다.
모바일 "다시 시도" 버튼이 무의미해지는 상황.

이 PR은 `POST /v1/analyses`가 **기존 failed 행을 제자리에서 재추론·갱신**하도록 만든다
(id 보존). success 행은 기존대로 멱등 반환(재과금·재실행 0), 행이 없으면 기존 생성 경로(201).

## 동작 (Behavior)

| 기존 행 상태 | 동작 | 응답 |
|---|---|---|
| `success` | 재실행 없이 그대로 반환(멱등) — **변경 없음** | 200 |
| `failed` | **같은 row 재추론 + 제자리 UPDATE**(id 유지, status/risk/health/rawResponse/latency/error/analyzedAt/updatedAt 갱신, recommendations 교체) | 200(성공) / 200(또 실패, 새 error) |
| 없음 | 기존 생성 경로 — **변경 없음** | 201 |

- **quota**: 기존 코드가 이미 **reserve-then-refund**(실패 시 `refundQuota`)라 failed 행은
  quota를 소비하지 않은 상태다. 재시도도 신규와 **동일한 reserve/refund 경로**를 그대로 탄다
  (무료·이메일검증 게이트 포함). 별도 우회/보상 로직 없음.
- **동시성**: `retryFailedAnalysis`가 트랜잭션 안에서 `UPDATE ... WHERE id=? AND status='failed'`
  **compare-and-set**. 동시 재시도의 loser는 0행 갱신 → winner가 확정한 현재 행을 재조회해
  그대로 반환(중복 write·중복 recommendations 방지). 추론 자체의 중복 호출까지는 막지 않는
  MVP 가드(과금은 무료 quota로 이중 방어).

## 산출물 (Deliverables)

### packages/database (재시도 쿼리 — 직접 SQL은 여기서만)
- `src/queries/analyses.ts`:
  - `findFailedAnalysisByImage(db, imageId, userId)` — 소유권 검증 포함 failed 행 조회
    (`findSuccessAnalysisByImage` 미러). success short-circuit 이후에만 호출됨.
  - `retryFailedAnalysis(db, {analysisId, modelId, analysis, recommendations})` — CAS UPDATE +
    recommendations 전량 삭제 후 재삽입(교체)을 한 트랜잭션에. loser는 현재 행 재조회 반환.
    `updatedAt`은 명시 set(0.29.5 `$onUpdate` 미지원, `_shared.ts`). `RetryAnalysisInput` export.

### apps/api (라우트 분기)
- `src/routes/analyses.ts` — `AnalysesDeps`에 `findFailedByImage` / `retryAnalysis` 추가.
  POST 핸들러: success short-circuit 다음에 `findFailedByImage`로 `isRetry` 판정 → 실패/성공
  저장 시 `isRetry`면 `retryAnalysis`(제자리 갱신, **200**), 아니면 기존 `storeAnalysis`
  (신규 201·실패 200). 재시도 응답의 recommendations는 `getRecommendations`로 재조회(CAS-loser
  정합).
- `src/app.ts` — `findFailedByImage`(→`findFailedAnalysisByImage`), `retryAnalysis`
  (→`retryFailedAnalysis`) 와이어링.
- `src/routes/analyses.test.ts` — `baseDeps`에 신규 dep 목 추가 + 재시도 3건:
  (a) failed→성공 재시도 = 같은 id·200·recs 2개·`storeAnalysis` 미호출,
  (b) failed→또 실패 = 같은 id·status failed·recs []·refund 호출,
  (c) success면 `findFailedByImage`/`retryAnalysis` 자체를 안 탐(순서 보장).

### apps/mobile (재시도 UI)
- `lib/features/analyses/presentation/report_screen.dart` — 실패 상태 블록을 `_RetrySection`
  (ConsumerStatefulWidget, 수기 Riverpod·코드젠 없음)으로 교체: 사유 안내 카드 + `l10n.commonRetry`
  ("다시 시도") PrimaryButton. 같은 `(hiveId, imageId)`로 `create` 재요청 → 성공 시 per-hive
  캐시(`latestAnalysisProvider`/`hiveAnalysesProvider`) 무효화 후 새 레포트로 `pushReplacement`.
  결과 전 오류(네트워크/quota)는 스낵바로 표시하고 화면 유지. (기존엔 실패 시 재시도 수단 없음.)

### docs
- `docs/01-development/frontend-api-integration.md` §4 — 재시도 계약 한 줄 추가(같은 imageId
  재요청 시 failed 행 제자리 갱신, 성공 200/재실패 200, success는 멱등, quota reserve/refund).

## 검증 (Verification)

- `pnpm --filter api test` — **170 passed** (기존 167 + 재시도 3). 전 스위트 green.
- `pnpm --filter api type-check` / `pnpm --filter @helpbee/database type-check` — clean.
- `cd apps/mobile && flutter analyze` — **0 issues**. (flutter test는 이 Mac Xcode 라이선스
  이슈로 미실행 — 위젯 테스트는 다음 실행 가능 환경에서.)
- pytest(apps/ai)는 이 PR에서 미변경 → 미실행.
- **라이브 E2E** (로컬 API:3001, AI:8000, beekeeper1 / hive 91adddd8…):
  1. AI 다운 상태에서 presign→S3 PUT(200)→confirm(image `4e4498d9…`)→POST /analyses →
     `HTTP 200 · id 20a5be8c… · status failed · error ai_unavailable · analyzedAt 13:17:20 · recs []`.
  2. AI 기동 후 같은 `{hiveId, imageId}` 재POST →
     `HTTP 200 · id 20a5be8c…(동일) · status success · risk 70 · health warning · error null ·
     analyzedAt 13:17:56(갱신) · recs 2`. → **같은 row 제자리 갱신 확인**.
  3. `GET /v1/analyses/20a5be8c…` → status success·risk 70·recs 2 (일관).
  4. success 상태에서 다시 재POST → `HTTP 200 · 같은 id · analyzedAt 13:17:56(불변)` →
     **success는 재실행 안 함** 확인.

## 후속 작업 (Follow-up)

- 추론 중복 호출까지 막는 강한 동시성 가드(재시도 직전 `status='pending'` pre-claim)는 MVP
  범위 밖 — 현재는 CAS write 가드 + 무료 quota로 이중 방어.
- 재시도 성공 시 엔진이 바뀌면(paid auto→openai) `model_id`가 교체됨 — 같은 이미지에 해당
  엔진 행이 이미 있으면 UNIQUE 충돌 가능(현 데이터·무료 yolo 경로에선 미발생). 베타 dual 노출 시 점검.
- flutter test 실행 가능 환경에서 `_RetrySection` 위젯 테스트 추가.

## 참조

- API 권위 가이드: `apps/api/CLAUDE.md` §5 Analyses, DB: `packages/database/CLAUDE.md`
  (dual-engine `UNIQUE(image_id, model_id)`, forward-only 마이그레이션)
- 계약: `docs/01-development/frontend-api-integration.md` §4
- 선행 스택: [2026-07-04-analysis-recommendations.md](./2026-07-04-analysis-recommendations.md) (#36)
