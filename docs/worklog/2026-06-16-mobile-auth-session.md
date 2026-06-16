# 2026-06-16 작업 정리 — 프론트엔드(모바일) 킥오프: scaffold + 인증

> 한 줄 결론: Figma 디자인을 받아 **Flutter 앱을 처음부터 부팅하고 인증 플로우 전체를 구현·검증**, **PR #26**(`feature/mobile-scaffold-auth` → `develop`)으로 올림.
> 관련 문서: 기술 기록 [`docs/05-implementation/2026-06-16-mobile-scaffold-auth.md`](../05-implementation/2026-06-16-mobile-scaffold-auth.md) · 실행 가이드 [`apps/mobile/RUNNING.md`](../../apps/mobile/RUNNING.md)

---

## 1. 이번 세션 목표

- 직전까지: 프론트 설계 + **백엔드 구현 완료**(auth/hives/images/analyses/subscriptions/admin 계약 고정).
- 이번: 방금 끝난 **Figma 디자인을 기준으로 모바일 앱 개발 시작**.
- 합의된 범위(사용자 선택): **기반 scaffold + 인증까지**, Figma는 **URL로 직접 연동**, 오프라인 캐시는 **hive**(단, 인증 단계엔 미사용 → 다음 마일스톤 배선).

## 2. 진행 과정 (단계별)

1. **상태 점검** — 백엔드/DB/연동가이드는 완성, `apps/mobile`은 `CLAUDE.md`+빈 디렉터리뿐(`flutter create` 전)임을 확인.
2. **Figma 추출** — Figma MCP로 디자인 토큰·화면 읽음. 스플래시/온보딩/로그인/홈/벌통/카메라/레포트 등 20여 화면 전체 확인. 인증 범위의 정확한 토큰 확보(아래 §4). *(Starter 플랜 호출 한도로 일부 화면은 메타데이터 기반.)*
3. **기반 구축** — `flutter create` + 의존성 해소. 여러 버전 충돌을 풀며 핵심 결정 확정(§3).
4. **병렬 구현(Workflow A)** — 정밀 스펙 1개 → 에이전트 병렬: `infra-core` ‖ `design-system` → `auth-logic` → `auth-UI/라우팅/main`.
5. **codegen/검증** — `flutter gen-l10n` + `flutter analyze`(0) + 위젯 테스트. (build_runner는 §3 사유로 폐기)
6. **적대적 검증(Workflow B)** — 5개 독립 리뷰어: 백엔드 계약 / Figma 정합 / 아키텍처 / 토큰 보안 / 완전성. **critical 1 + major 5 + minor 15** 발견.
7. **수정 반영** — critical/major 전부 + 가치 높은 minor 수정(§5).
8. **최종 검증** — analyze 0 / test 10 / **iOS 시뮬 빌드 성공**(빌드는 수정 전후 2회 확인).
9. **PR** — 커밋·푸시·**PR #26** 생성(GitHub MCP 토큰 만료로 `gh` CLI 사용).

## 3. 주요 의사결정 + 근거

| 결정 | 근거 |
|---|---|
| **freezed/json/build_runner 미사용** → DTO·sealed state 수기 | Dart 3.10이 네이티브 build hook(`objective_c`)과 충돌, build_runner가 `'dart compile' does not support build hooks`로 실패. 툴체인이 `dart build` 지원 시 재도입 |
| **Riverpod 수동**(Notifier/NotifierProvider) | riverpod_generator 4.x가 이 SDK와 버전 충돌. 수동도 v3에서 완전히 idiomatic |
| **flutter_secure_storage 9.x 핀** | 10.x가 `objective_c`(Apple FFI) 유발 → build_runner 깨짐. 9.x는 동일 API |
| **hive는 인증 단계 미배선** | 토큰=secure_storage, 온보딩 플래그=shared_preferences로 충분. hive는 오프라인 캐시(다음 마일스톤)용 |
| **세션 상태 `core/session` 이전 보류** | home→auth 교차 import 정리는 다음 home/네비게이션 마일스톤과 함께(임시 placeholder 1곳, churn 회피) |

확정 의존성: flutter_riverpod 3.3 · go_router 17.3 · dio 5.9 · flutter_secure_storage 9.x · google_fonts 8.1 · intl 0.20.

## 4. Figma 디자인 토큰 (실제 추출값)

- CTA `#FFD869` · 로고(Jua) `#F9CA46` · 딥앰버 `#E79D04` · 체크 `#FFE18C`
- 스플래시 배경 `#18130C` · 본문 배경 `#FDFCF9` · 입력 보더/힌트 `#B9B9B9` · 텍스트 `#18130C`/`#3C3C3C`
- 입력 라운드 12 · CTA 라운드 14·높이 56 · 로고 폰트 **Jua**, 본문 **Noto Sans KR**

## 5. 산출물 (PR #26, 118 files)

- **core/**: config(API_BASE) · errors(19 ErrorCode+AppException) · api(problem+json/봉투 파서, bareDio/authDio, **single-flight refresh**, 재귀 redaction) · storage(token·prefs) · routing(go_router redirect) · theme(Figma 토큰)
- **features/auth/**: data(수기 DTO·api·repository) · domain(인터페이스) · presentation(sealed state·Notifier·검증·에러매핑·스플래시/온보딩/로그인/회원가입)
- **features/home/**: 임시 placeholder
- **shared/widgets/**: PrimaryButton·AppTextField·BrandWordmark 등
- **lib/main.dart** · **l10n**(ko, 60+키) · **test/**(위젯 3 + DTO/에러 7)
- **검증 후 수정**: 무한 splash 방지 · keepLoggedIn 실배선 · secure storage 하드닝 · refresh grace/codeless-401 분기 · Retry-After 노출 · 로그 재귀 redaction · logout via bareDio · 403 폴백 · show/hide i18n · scrim 토큰화 · 스플래시 화이트 워드마크 · 비번 힌트 정합

## 6. 검증 결과

- `flutter analyze` → **0 issues**
- `flutter test` → **10 passing**
- `flutter build ios --simulator --debug --no-codesign` → **성공**(`Runner.app`, `kr.helpbee.helpbee`)
- 5-lens 적대적 검증 통과(핵심 결함 전부 수정)

## 7. 현재 백엔드 연동 상태

| 영역 | 상태 |
|---|---|
| **로그인/회원가입/토큰/세션 복원** | ✅ 실호출 코드 완비 — 백엔드(`localhost:3001`) 띄우면 즉시 동작 |
| 벌통(Hive)/이미지 업로드/분석 | 백엔드 계약 존재, **모바일 화면·호출은 다음 마일스톤** |
| AI 분석 결과 | 백엔드 추론 자체가 미동작(readiness §10 GAP) |

## 8. 알려진 제약

- freezed/build_runner 비활성(위 §3) · 폰트 google_fonts 런타임 페치(Pretendard 번들 후속)
- SNS 로그인·아이디/비번 찾기 = 디자인 반영용 **비활성(준비중)**, Figma 일러스트는 placeholder
- AI/이메일 인증 발송/recommendations = 백엔드 GAP

## 9. 다음 단계

1. (선택) 지금 인증을 **백엔드 띄워 실제로 돌려보기** — `apps/mobile/RUNNING.md`
2. **벌통(Hive) CRUD + 실데이터 홈** (`/v1/hives` 연동) ← 다음 우선순위
3. 카메라/presign 업로드(`/v1/images`) → 분석 결과 화면(실패상태 우선)
4. 리팩토링: 세션 상태 `core/session` 이전(home/네비게이션 패스와 함께)

## 10. 참조

- PR: https://github.com/hyunshu12/HelpBee/pull/26
- 권위 가이드: `apps/mobile/CLAUDE.md` · 백엔드 계약: `docs/01-development/frontend-api-integration.md`
- 실행: `apps/mobile/RUNNING.md` · 기술 기록: `docs/05-implementation/2026-06-16-mobile-scaffold-auth.md`
