# 2026-06-16 — 모바일 벌통(Hive) CRUD + 실데이터 홈, 로컬 DB·백엔드 연결

> PR: (예정) · 브랜치: `feature/mobile-hives-integration` → develop · 머지일: (예정)

## 범위 (Scope)

로컬 개발 스택(Postgres·Redis·API)을 실제로 띄워 인증 플로우의 실동작을 검증하고, 모바일 앱에
**벌통(Hive) CRUD + 실데이터 홈**을 `/v1/hives`에 연동했다. (직전 마일스톤 = scaffold + 인증까지)

## 산출물 (Deliverables)

### 로컬 스택 기동 (코드 산출물 아님 — 환경 기록)
- 로컬 **Homebrew Postgres 16 + Redis 7** 사용(이 머신엔 Docker 미설치). `helpbee` DB + `helpbee_user` 롤 생성 → `pnpm --filter @helpbee/database migrate` → `seed:dev`.
- `apps/api/.env`(gitignored) 작성: `DATABASE_URL`/`REDIS_URL`/강시크릿(`JWT_SECRET`≥64·`REFRESH_TOKEN_PEPPER`≥32·`AI_INTERNAL_HMAC_SECRET`≥32, 상호 상이)/`S3_IMAGES_BUCKET`/`AI_BASE_URL`/`CORS_ALLOWLIST`.
- 백엔드 `localhost:3001` 기동 → 라이브 검증(아래 §검증).
- 시드 계정(전부 email_verified): `beekeeper1@helpbee.local`(벌통 3) · `beekeeper2@helpbee.local`(벌통 2) · `admin@helpbee.local` / 공통 비번 `helpbee-dev-2026`.

### 모바일 — 벌통 feature (`apps/mobile/lib/features/hives/`)
- `data/hive_dto.dart` — `Hive`/`HiveDeletion` 수기 DTO. ⚠️ lat/lng는 백엔드가 **문자열**로 주므로 double 파싱, nullable 필드 관용 처리.
- `data/hives_api.dart` — `/v1/hives` 데이터소스(list/getById/create/update/delete). `{data,meta}` 봉투 unwrap, pagination, `_guard`로 DioException→AppException. 좌표 pair 규칙(둘 다/둘 다 아님) 클라 가드.
- `domain/hives_repository.dart` — 도메인 인터페이스.
- `data/hives_repository_impl.dart` — 구현 + `hivesRepositoryProvider`.
- `presentation/hives_list_controller.dart` — `AsyncNotifier<List<Hive>>`. **build()는 인증 사용자 id에 스코프**(로그아웃/타사용자 로그인 시 자동 재조회). create=낙관적 prepend(데이터 있을 때만, 아니면 재조회), delete=낙관적 제거, refresh=`AsyncValue.guard`(목록 유지).
- `presentation/hive_detail_controller.dart` — `FutureProvider.autoDispose.family<Hive,String>`(삭제·재방문 시 stale 캐시 방지).
- `presentation/hives_list_view.dart` — 목록 렌더(loading/error/empty/list, pull-to-refresh, 상세 push).
- `presentation/hive_detail_screen.dart` — 상세(필드 표시 + 삭제 확인) + "진단 이력 = 다음 업데이트" 플레이스홀더 섹션.
- `presentation/create_hive_sheet.dart` — 벌통 등록 bottom sheet(이름 필수, 주소·메모 선택) + `createHiveAndNotify` 헬퍼.

### 모바일 — 공유/홈/코어/라우팅/l10n
- `shared/widgets/hive_card.dart`, `shared/widgets/empty_state.dart` — 재사용 위젯.
- `core/errors/error_messages.dart` — feature-agnostic `appErrorMessage`/`errorCodeMessage`(core 위치라 hives가 auth를 import하지 않고 사용).
- `features/home/presentation/home_screen.dart` — 홈 **셸**(AppBar 인사+로그아웃, FAB 등록, body=`HivesListView`). `home_placeholder_screen.dart`는 trash 제거.
- `core/routing/route_paths.dart`·`app_router.dart` — `/home`→`HomeScreen`, `/hives/:id`→`HiveDetailScreen` 추가.
- `lib/l10n/app_ko.arb` — 벌통 관련 키 + 에러 키(`errNotFound`/`errQuota`/`errAiUnavailable`) 추가 → `flutter gen-l10n` 재생성.
- 테스트: `test/hive_parsing_test.dart`(DTO) · `test/hive_card_test.dart`(위젯) · `test/hives_list_controller_test.dart`(낙관적 업데이트 가드/사용자 스코프, retry 비활성 컨테이너).

## 검증 (Verification)

- **라이브 백엔드 E2E(curl)**: `POST /v1/auth/login`(beekeeper1) → `GET /v1/hives`(시드 3건) → `POST /v1/hives`(201) → `GET /v1/auth/me`(subscription) 모두 정상. `/health` ok.
- `flutter analyze` → **0 issues**.
- `flutter test` → **21 passing**(DTO·위젯·컨트롤러).
- `flutter build ios --simulator --debug --no-codesign` → **성공**(`Runner.app`).
- **적대적 3-렌즈 리뷰**(계약/아키텍처/런타임) 후 결함 반영: ① 비-data 상태 낙관적 create/delete가 실목록 파괴 → 가드+재조회, ② 로그아웃 후 타사용자 목록 누수 → build() 사용자 스코프, ③ pull-to-refresh 목록 깜빡임 → guard 유지, ④ 좌표 pair 클라 가드, ⑤ home→hives **data-layer** import 제거(홈=셸, 리스트=hives feature 소유), 토큰 nit.

### 알려진 제약 / 후속 검증
- 등록 폼은 **이름/주소/메모만**(좌표 수집 X) — 위치는 GPS 캡처로 후속.
- `meta.pagination.total`은 현재 백엔드가 페이지 길이를 반환(전체 카운트 아님) — 목록 UI 미사용.
- AI 분석/이미지 업로드/recommendations 화면은 범위 밖(다음 마일스톤, 백엔드 GAP 존재 — `frontend-api-integration.md` §10).
- 실기기/시뮬 라이브 UI 구동은 수동(자동화된 통합 테스트는 다음 단계).

## 후속 작업 (Follow-up)

- 카메라/presign 업로드(`/v1/images`) → 분석 결과 화면(실패상태 우선) → fl_chart 추이.
- 세션 상태 `core/session` 이전(home/네비게이션 패스와 함께) — home→auth, home→hives(셸), hives→auth(세션 스코프) 교차 import 정리.
- 등록/수정에 위치(GPS) 캡처 추가.

## 참조

- 권위 가이드: `apps/mobile/CLAUDE.md`
- 백엔드 계약: `docs/01-development/frontend-api-integration.md` (§2 Hives, §10 Readiness)
- 직전 마일스톤: [2026-06-16-mobile-scaffold-auth.md](./2026-06-16-mobile-scaffold-auth.md)
- 로컬 실행: `apps/mobile/RUNNING.md`
