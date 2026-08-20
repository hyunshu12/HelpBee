# 2026-08-20 — 진단 이력 탭 (전체 벌통 이력)

> 브랜치: demo/2026-08-12 · PR: (미생성)

## 범위 (Scope)

하단 네비게이션 "진단 이력" 탭이 진단을 아무리 해도 항상 빈 화면이던 문제를 고쳤다.
`GET /v1/analyses`의 `hiveId`를 optional로 열어 **전체 벌통 이력**을 제공하고, 플레이스홀더였던
모바일 화면을 실제 목록으로 교체했다.

## 원인 (Root cause)

두 겹이었다.

1. **모바일**: `analysis_history_screen.dart`가 하드코딩된 `EmptyState` 하나였다. API 호출 코드가
   아예 없었다(코드 주석에 "Phase 3에서 연결" 이라고 적힌 채 남아 있었음).
2. **백엔드**: `listAnalysesQuerySchema.hiveId`가 **필수**라 벌통을 지정하지 않으면 400.
   전체 이력을 받을 엔드포인트 자체가 없었다 → 모바일이 붙을 곳이 없었던 게 1의 실제 이유.

데이터 저장 자체는 정상이었다(라이브 확인: 사용자 1명 기준 35건 적재됨). 벌통 상세 화면의
"과거 진단 이력"에서는 원래도 보이고 있었다.

## 산출물 (Deliverables)

**백엔드**

- `apps/api/src/schemas/analyses.ts` — `hiveId`를 `.optional()`로. 주면 해당 벌통, 안 주면 전체.
  잘못된 uuid는 여전히 400(optional ≠ 아무거나 허용).
- `packages/database/src/queries/analyses.ts` — `listAnalysesForUser()` 신규.
  `hives` INNER JOIN + `userId` 필터로 IDOR 차단, soft-deleted 벌통 제외.
  정렬은 `analyzedAt DESC NULLS LAST, createdAt DESC, id DESC` —
  ① `analyzedAt`이 nullable(pending)이라 PG 기본 DESC면 미완료 건이 맨 위로 올라오고,
  ② 같은 `analyzedAt`이 여러 건 존재(실측: 한 벌통에 10건 동일 timestamp)해서
  tie-breaker가 없으면 offset 페이지네이션에서 행이 중복/누락된다.
- `apps/api/src/routes/analyses.ts` — `listForUser` dep 시그니처를 `hiveId: string | undefined`로.
- `apps/api/src/app.ts` — `hiveId === undefined`면 `listAnalysesForUser`, 아니면 기존 per-hive 쿼리로 분기.

**모바일**

- `apps/mobile/lib/features/analyses/data/analyses_api.dart` — `listAll()` + `allAnalysesProvider`.
- `apps/mobile/lib/features/analyses/presentation/analysis_history_screen.dart` — 전면 교체.
  로딩 / 에러(+다시 시도) / 빈 상태 / 목록 + pull-to-refresh. 카드 탭 → 해당 진단 리포트.
  벌통 이름은 `hivesListControllerProvider`에서 클라이언트 조인(분석 페이로드에 이름이 없음).
- `analysis_run_controller.dart`, `report_screen.dart` — 새 진단/재시도 성공 시
  `allAnalysesProvider` invalidate 추가(탭이 즉시 최신화되도록).

**문서**

- `docs/01-development/frontend-api-integration.md` §4 — `hiveId?` 계약 반영.

## 검증 (Verification)

- `pnpm --filter @helpbee/api test` — **212 passed** (신규 3건: hiveId 생략/지정/잘못된 uuid)
- `pnpm --filter @helpbee/api type-check`, `--filter @helpbee/database type-check` — clean
- `flutter test` — **40 passed** (신규 5건: 다중 벌통 목록 / 빈 상태 / 에러≠빈상태 구분 /
  실패 카드 오버플로 / 벌통 이름 못 찾아도 카드 유지)
- `dart analyze` — No issues found
- **라이브 (API :3001 + 시드 계정)**
  - `GET /v1/analyses` (hiveId 없이) → 35건. 벌통별 합계(1+2+22+10)와 정확히 일치
  - 오프셋 10씩 4페이지 수집 → 35건 고유, **중복 0** (동일 timestamp 구간 포함) →
    tie-breaker 동작 확인
  - 다른 사용자(beekeeper2/admin) 토큰 → 0건 → IDOR 격리 확인
  - `?hiveId=not-a-uuid` → 400
- **라이브 (모바일 클라이언트 경유)** — 실제 `Dio` + 실서버로 `AnalysesApi.listAll()` 호출 →
  35건 파싱, 최신순 유지, tier 파생 정상 (일회성 스모크, 커밋 안 함)

### 알려진 제약

- 시뮬레이터에서 화면을 **직접 탭해서** 확인하지는 못했다. 합성 클릭이 iOS Simulator에
  전달되지 않아(orca computer-use) 로그인 폼을 통과할 수 없었다. 위젯 테스트 + 실서버
  클라이언트 스모크로 대체 검증했고, 앱 빌드·기동 자체는 성공했다.
- **목록은 최신 100건까지**(백엔드 max page size). 무한 스크롤은 넣지 않았다 —
  offset 페이지네이션은 새 진단이 들어오면 경계가 밀리므로 cursor 계약이 필요하다.
- Bruno 컬렉션(`apps/api/bruno/`)이 `.gitkeep`만 있는 빈 상태라 요청을 추가하지 않았다.
  컬렉션 스캐폴딩은 이 변경의 범위 밖.

## 후속 작업 (Follow-up)

- 100건 초과 사용자 대비 cursor 기반 `GET /v1/analyses` (그때 무한 스크롤)
- Bruno 컬렉션 스캐폴딩 + analyses 요청 일괄 추가
- `listAnalysesByHiveForUser`(per-hive)도 같은 tie-breaker 정렬 적용 — 지금은 신규 쿼리에만 넣었다
- 모바일 `integration_test/` 셋업(현재 빈 디렉터리, pubspec에 의존성 없음)

## 참조

- `apps/api/CLAUDE.md`, `packages/database/CLAUDE.md`, `apps/mobile/CLAUDE.md`
- 계약: `docs/01-development/frontend-api-integration.md` §4
