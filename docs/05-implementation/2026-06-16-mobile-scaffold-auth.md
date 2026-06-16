# 2026-06-16 — Flutter 모바일 scaffold + 인증 플로우

> PR: (예정) · 브랜치: feature/mobile-scaffold-auth → develop · 머지일: TBD

## 범위 (Scope)

`apps/mobile`을 `flutter create`로 부팅하고, **인증 플로우 전체**(스플래시 · 온보딩 3p · 로그인 · 회원가입 · 홈 placeholder)를 Figma 디자인 + 백엔드 계약(`frontend-api-integration.md` §1) 기준으로 구현. 토큰 회전/단일비행 refresh/세션 복원까지 포함.

## 산출물 (Deliverables)

**기반 / 설정**
- `apps/mobile/pubspec.yaml` — 의존성 확정: flutter_riverpod 3.3, go_router 17.3, dio 5.9, flutter_secure_storage **9.x**(10.x는 objective_c build-hook로 build_runner 비호환), google_fonts 8.1, intl 0.20. **freezed/json/build_runner 미사용**(Dart 3.10 네이티브 build hook 비호환) → DTO·sealed state 수기 작성.
- `apps/mobile/l10n.yaml`, `lib/l10n/app_ko.arb` — ko 단일 로케일, 60+ 키. 생성물 `lib/l10n/app_localizations*.dart`.
- `apps/mobile/RUNNING.md` — 로컬 시뮬레이터 실행 가이드(iOS 권장, Android 10.0.2.2, dart-define API_BASE).

**core/**
- `core/config/app_config.dart` — API_BASE(dart-define, 기본 localhost:3001) + /v1 prefix
- `core/errors/{error_code.dart,app_exception.dart}` — 19개 ErrorCode + 와이어 매핑 + AppException(retryAfter 포함)
- `core/api/{problem_details,api_envelope,dio_client,auth_interceptor,logging_interceptor,refresh_coordinator}.dart` — problem+json/{data,meta} 파서, bareDio/authDio, 401→single-flight refresh→1회 재시도, 재귀 redaction
- `core/storage/{token_store,app_prefs}.dart` — access(메모리)/refresh(secure storage, Keychain first_unlock_this_device + Android encrypted) + onboarding/keepLoggedIn 플래그
- `core/routing/{route_paths,app_router}.dart` — go_router + AuthFlowState 기반 redirect + refreshListenable
- `core/theme/{app_colors,app_typography,app_radius,app_spacing,app_theme}.dart` — Figma 토큰(꿀색 팔레트, Jua 로고/Noto Sans KR 본문)

**features/auth/**
- `data/{auth_dto,auth_api,auth_repository_impl}.dart` — 수기 DTO(PublicUser/AuthTokens/AuthSession/SubscriptionBrief/MeResult), signup/login/refresh/logout/me, 토큰 영속
- `domain/auth_repository.dart` — 인터페이스(+ forgetLocalSession)
- `presentation/{auth_flow_state,auth_controller,auth_error_message,auth_validators}.dart` — 네이티브 sealed state, Notifier 부트스트랩(crash-safe), 코드→한글 메시지, 폼 검증
- `presentation/{splash,onboarding,login,signup}_screen.dart` + `widgets/sns_login_row.dart`

**features/home/** — `presentation/home_placeholder_screen.dart` (다음 마일스톤 전 임시)
**shared/widgets/** — PrimaryButton, SecondaryButton, AppTextField, LoadingOverlay, BrandWordmark
**lib/main.dart** — ProviderScope + MaterialApp.router + ko 로케일 + light/dark
**test/** — `widget_test.dart`(3) + `auth_parsing_test.dart`(7, DTO/error 매핑)

## 검증 (Verification)

- `flutter analyze` → **0 issues**
- `flutter test` → **10 passing**
- `flutter build ios --simulator --debug --no-codesign` → **성공**(`Runner.app`, bundle `kr.helpbee.helpbee`)
- 5-lens 적대적 검증(워크플로) 통과: 백엔드 계약 정합, Figma 토큰 hex 일치, 아키텍처(코어 외 Dio 금지·토큰 secure 전용·redaction), 토큰 보안, 완전성. 발견 1 critical + 5 major + 다수 minor → 핵심 전부 수정 반영(아래).
- **수정 반영**: 부트스트랩 crash-safe(무한 splash 방지), keepLoggedIn 실제 배선, secure storage 하드닝, refresh grace/codeless-401 분기, Retry-After 노출, 로그 재귀 redaction, logout via bareDio, 403 폴백, show/hide 툴팁 i18n, scrim 토큰화, 스플래시 워드마크 화이트, 비밀번호 힌트 정합.

### 알려진 제약 / 후속 검증
- **freezed/build_runner 비활성**: Dart 3.10 + objective_c 네이티브 build hook 비호환. 툴체인이 `dart build` 지원 시 재도입.
- **codegen 미사용**으로 DTO/Provider/state 전부 수기. Riverpod도 수동(NotifierProvider).
- AI 분석/이메일 인증 발송/recommendations는 **백엔드 GAP**(readiness §10) — 결과 화면은 다음 마일스톤에서 실패상태 우선.
- SNS 로그인·아이디/비번 찾기 = 디자인 반영용 **비활성(준비중)**. Figma 일러스트는 placeholder 아이콘.
- 폰트 google_fonts 런타임 페치(Pretendard 번들은 후속 TODO).

## 후속 작업 (Follow-up)

- **아키텍처 디퍼**(의도적 보류): 세션/네비 상태(AuthController/AuthFlowState)를 `core/session`으로 이전 → home→auth 교차 import + domain→data 레이어링 정리. **다음 home/hives 마일스톤의 네비게이션 패스와 함께** 수행.
- 다음 가능 PR: 벌통(Hive) CRUD + 홈(실데이터) → 카메라/presign 업로드 → 분석 결과(실패상태) 화면.
- 폴리시: 스플래시 지연(>5s) 폴백 UI, SNS 브랜드 에셋, admin/구독 에러코드 확장.

## 참조

- 권위 가이드: `apps/mobile/CLAUDE.md`
- 백엔드 계약: `docs/01-development/frontend-api-integration.md` (§1 auth, §1.1 토큰, §10 readiness)
- 실행: `apps/mobile/RUNNING.md`
- Figma: design file `nxpjoTDvnfAAAnsW2iOXcy` (토큰 추출분 — 호출 한도로 일부 화면은 메타데이터 기반)
