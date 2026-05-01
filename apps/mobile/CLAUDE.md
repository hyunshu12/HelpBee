# HelpBee Mobile App — CLAUDE.md

이 문서는 `apps/mobile/` (Flutter) 작업에 들어오는 모든 AI 에이전트를 위한 cold-pickup 가이드다. 코드는 아직 한 줄도 없고, 디렉터리 골격과 본 문서만 존재한다.

---

## 1. 목적

HelpBee의 메인 사용자 클라이언트(iOS / Android). 양봉가가 벌통을 촬영하고 **5초 이내에** 진단 결과(병해충 위험도, tier, 권장 조치)를 받는 것이 핵심 UX 목표다.

- 단일 앱 = 단일 사용자 페르소나(양봉가)
- B2B 관리자 / 전문가용 화면은 별도 도메인(`apps/web` 등)에서 다룸
- 본 앱은 "현장에서 한 손으로 5초 안에" 동작해야 한다

관련 도메인:
- `services/api` — REST API (auth, hives, analyses, presigned-url)
- `services/inference` — 이미지 추론 (앱은 직접 호출하지 않음, API 경유)
- `packages/shared-types` — 공유 DTO/스키마

---

## 2. 초기 셋업 (아직 미실행 — 다음 작업자가 실행)

본 디렉터리는 `flutter create` 이전 상태다. `lib/`, `test/`, `assets/` 등의 디렉터리 골격이 미리 잡혀 있어, `flutter create`가 그 위에 `main.dart`, `pubspec.yaml`, 플랫폼 폴더(`ios/`, `android/`)만 채워 넣게 된다.

### 2.1 Flutter SDK
- channel: **stable**
- 최소 버전: **>= 3.22**
- Dart: 3.4+

### 2.2 첫 실행 명령
`apps/mobile/` 디렉터리 안에서:

```bash
flutter create \
  --org kr.helpbee \
  --project-name helpbee \
  --platforms=ios,android \
  .
```

- `.`(현재 디렉터리) 위에 적용되므로 기존 `lib/`, `test/`, `assets/` 트리는 보존된다.
- 생성 후 `lib/main.dart`는 placeholder다 — 곧바로 라우팅/테마 진입점으로 교체할 것.
- `pubspec.yaml`도 새로 만들어진다 — 아래 §17 패키지 목록을 추가한다.

### 2.3 코드 생성기
freezed / json_serializable / riverpod_generator를 쓰므로 개발 시작 후:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

---

## 3. 타겟 사용자 / UX 원칙

### 사용자
- **30~60대 양봉가**. 모바일 앱 사용 경험 편차가 크다.
- **현장 환경**: 야외 햇빛, 장갑 착용, 한 손, 흔들리는 손, 시끄러운 주변.
- 한국어 모국어 화자 (1차 i18n 타겟 = `ko_KR`).

### UX 원칙
- **터치 타겟 최소 48dp**, 권장 56dp 이상. 버튼 간 간격 12dp+.
- **본문 폰트 18sp 이상**, 결과 핵심 숫자/tier는 28sp+ bold.
- **고대비**: WCAG AA 이상. 햇빛 아래 가독성을 우선.
- **5초 룰**: 홈 → 카메라 → 결과까지의 탭 수와 로딩 합계가 5초 안에 들어와야 한다.
- **에러는 사람 말로**: "네트워크 오류" 대신 "지금 인터넷이 약해요. 잠시 후 다시 시도해 주세요."
- **글자 폰트**: Pretendard 우선, 폴백으로 Noto Sans KR. 시스템 폰트는 마지막.

---

## 4. 아키텍처 — Feature-first

```
lib/
  core/                    횡단 관심사 (전 features가 의존)
    api/                   dio 인스턴스, interceptors, presigned upload
    storage/               secure storage, hive box, prefs wrapper
    theme/                 ColorScheme, TextTheme, ThemeData
    routing/               go_router 정의, redirect, deep-link
    errors/                AppException 계층, 표준 에러 매핑
  features/
    auth/                  data/ domain/ presentation/
    hives/                 data/ domain/ presentation/
    analyses/              data/ domain/ presentation/
    profile/               data/ domain/ presentation/
    onboarding/            data/ domain/ presentation/
  shared/
    widgets/               PrimaryButton, EmptyState, RiskBadge, RiskGauge
  l10n/                    ARB 파일 (app_ko.arb, app_en.arb)
  main.dart                (flutter create 이후 생성)
```

### 4.1 레이어 규칙
각 feature는 **3레이어**:
- `data/` — Repository 구현, DTO, datasource (remote/local)
- `domain/` — Entity, Repository **인터페이스**, UseCase (얇게)
- `presentation/` — Screen / Widget / Riverpod Provider / Controller

### 4.2 의존 방향
```
presentation → domain ← data
                 ↑
core (모든 곳에서 import 가능)
```

- presentation은 data를 직접 import 하지 않는다. domain의 Repository 인터페이스에만 의존.
- features 간 직접 import 금지. 공유는 `core` 또는 `shared/widgets`로.
- `core/api`가 모든 HTTP의 단일 진입점이다. features에서 dio를 직접 new 하지 않는다.

### 4.3 shared/widgets 후보
- `PrimaryButton`, `SecondaryButton` (48dp+ 보장)
- `EmptyState` (이력 없음, 네트워크 끊김 등)
- `RiskBadge` (tier별 색상/아이콘)
- `RiskGauge` (반원형, fl_chart 기반)
- `LoadingOverlay`

---

## 5. 상태 관리 — Riverpod 2

- **`flutter_riverpod`** + **`riverpod_generator`** + **`riverpod_annotation`**.
- **`AsyncNotifier` / `AsyncNotifierProvider`** 로 API 상태(loading/data/error) 관리.
- `Provider`는 가능하면 `@riverpod` annotation으로 코드 생성 (수동 `Provider((ref) => ...)`보다 안전).
- ViewModel 역할 = `Notifier` / `AsyncNotifier`. 화면은 `ref.watch`로만 구독.
- 전역 싱글턴(예: `Dio`, `SecureStorage`)도 Provider로 노출하여 테스트 시 override.

코드 생성:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

DTO나 provider 시그니처를 바꿨으면 watcher가 죽어 있는 경우 한 번 더 돌릴 것.

---

## 6. 라우팅 — go_router

- **선언형 라우트 트리**, `core/routing/app_router.dart`에 정의.
- **redirect**로 auth guard: 토큰 없는 사용자가 보호 라우트 진입 시 `/login`으로.
- 파라미터는 path-param 우선 (`/hives/:id`), 쿼리는 보조.
- **딥링크**:
  - `helpbee://hive/{id}` → 벌통 상세
  - `helpbee://analysis/{id}` → 진단 결과
  - iOS: associated domains / URL scheme `helpbee` 등록
  - Android: intent-filter

라우트 목록(개략):

```
/splash
/onboarding   (3-step)
/login
/signup
/home               (보호)
  /hives/:id        (보호)
    /capture        (보호, 카메라)
    /result/:aid    (보호)
/settings           (보호)
```

---

## 7. 주요 화면 흐름

```
Splash
  └─ (토큰 검사)
      ├─ 신규  → Onboarding (3 step) → Login/Signup → Home
      └─ 기존  → Home
                 ├─ Hive 목록
                 │   └─ Hive 상세
                 │       ├─ 진단 이력
                 │       └─ Camera (촬영 가이드 오버레이)
                 │           └─ Result (tier, 위험도, 권장 조치)
                 └─ Settings (프로필, 알림, 다크모드, 로그아웃)
```

진단 결과 화면(Result)은 본 앱의 **핵심 가치 전달 지점**이다. tier별 색/메시지/CTA를 디자인 시스템에서 일관되게.

---

## 8. 카메라 / 이미지

### 8.1 캡처
- **`camera`** 패키지: 인앱 카메라 + 가이드 오버레이(벌통 프레임 정렬용).
- **`image_picker`**: 갤러리에서 선택 폴백.
- 가이드 오버레이는 단순 `Stack` + `CustomPainter` (반투명 가이드 박스 + 텍스트).

### 8.2 후처리
- **`image`** 패키지로 디코드 → max **1920×1920** 리사이즈 (긴 변 기준), **JPEG q85** 인코드.
- iOS HEIC 입력은 **`flutter_image_compress`**로 JPEG 변환.
- EXIF orientation 반영, 위치정보(GPS)는 **제거**(개인정보 보호).

### 8.3 업로드
1. 앱이 API에 `POST /uploads/presigned` 호출 → `{ uploadUrl, imageKey }` 수신.
2. 앱이 `uploadUrl`로 **S3 직접 PUT**(dio bypass — 인증 헤더 제거).
3. 성공 시 `POST /analyses { hiveId, imageKey }` → 추론 비동기 시작.
4. 결과는 폴링 또는 푸시(§12). 단기는 폴링 5회 × 1초 → 미완료 시 백그라운드 큐.

---

## 9. API 통신

### 9.1 dio 구성 (`core/api/`)
- `Dio` 인스턴스 1개. baseUrl은 `--dart-define=API_BASE=...`로 주입.
- **Interceptor 체인**:
  1. `AuthInterceptor` — JWT 헤더 부착, 401 시 refresh-token 호출 → 원요청 1회 재시도.
  2. `RetryInterceptor` — 네트워크/5xx에서 **idempotent 메서드만** 지수 백오프(0.5s, 1s, 2s, max 3회).
  3. `LoggingInterceptor` — debug 빌드에서만 활성, body는 200KB cap.

### 9.2 DTO
- **`freezed`** + **`json_serializable`**.
- tier 같은 enum-ish 필드는 **freezed union** 또는 `@JsonEnum`으로 표현 (서버가 새 tier를 추가해도 앱이 죽지 않도록 `@JsonKey(unknownEnumValue: ...)`).
- 서버 스키마 변경 시 `services/api`와 `packages/shared-types`를 먼저 정렬한 뒤 본 앱의 DTO 갱신.

### 9.3 에러
- `core/errors/app_exception.dart`에 `NetworkException`, `AuthException`, `ServerException`, `ValidationException` 계층.
- dio `DioException` → `AppException` 매핑은 interceptor 또는 repository 경계에서 처리.
- presentation은 `AppException`만 본다.

---

## 10. 로컬 저장 (`core/storage/`)

| 용도                         | 패키지                       | 비고                                  |
| ---------------------------- | ---------------------------- | ------------------------------------- |
| 액세스/리프레시 토큰         | `flutter_secure_storage`     | **유일한 토큰 저장처**. 다른 곳 금지. |
| 진단 이력 캐시               | `hive` (또는 `isar`)         | 오프라인 열람용                       |
| 미전송 업로드 큐             | `hive`                       | 재시도 워커가 소비                    |
| 온보딩 완료 플래그, 다크모드 | `shared_preferences`         | 비민감 단순 플래그                    |

선택은 첫 구현자 재량(hive vs isar). 단 한 번 정해지면 features 전반 일관 사용.

---

## 11. 차트 — fl_chart

- **월별 진단 추이**: `LineChart`. x=일, y=평균 risk score 또는 진단 횟수.
- **결과 게이지**: 반원형 게이지 (fl_chart `PieChart` 변형 또는 커스텀 `CustomPainter`).
- 색상은 `core/theme`의 ColorScheme에서만 가져온다 — 차트에 hex 직접 박지 말 것.

---

## 12. 푸시 / 로컬 알림

- **`firebase_messaging`** (FCM) — 서버에서 진단 완료 시 트리거.
- **`flutter_local_notifications`** — 포그라운드 알림 표시, 사용자 알림(점검 리마인더 등).
- iOS: APNs 인증서/키, `UIBackgroundModes: remote-notification`.
- Android: **API 33+ `POST_NOTIFICATIONS` 권한** 런타임 요청.
- 알림 탭 → 딥링크 처리 (§6).

---

## 13. i18n

- `flutter_localizations` + `intl` + ARB.
- `lib/l10n/app_ko.arb` (primary), `app_en.arb` (보조).
- `pubspec.yaml`에 `flutter: generate: true`, `l10n.yaml` 설정 후 `flutter gen-l10n`.
- 하드코딩 한글 금지 — 모든 사용자 노출 문자열은 ARB 경유.
- 날짜/숫자 포매팅은 `intl`의 `DateFormat`, `NumberFormat`. 단위(섭씨/화씨, kg/lb)는 i18n과 분리된 사용자 설정으로.

---

## 14. 테마

- **Material 3** (`useMaterial3: true`).
- **Seed color**: `#F4B400` (꿀색 / honey amber). `ColorScheme.fromSeed(seedColor: ...)`.
- **Error**: `#D32F2F`.
- 다크모드 토글 — 시스템 따라가기 / 강제 라이트 / 강제 다크 3-state.
- 폰트: Pretendard → Noto Sans KR → 시스템.
- `core/theme/app_theme.dart`에 `lightTheme`, `darkTheme` 두 개 export.

### tier 색상 (디자인 토큰)
- `tier.safe` — 초록 계열
- `tier.warn` — 앰버/오렌지
- `tier.danger` — 빨강
- `tier.unknown` — 회색
실제 hex는 디자인 시스템 정의를 따른다 — 본 문서에 박지 말고 `theme`에서 노출.

---

## 15. 테스트

### 15.1 Unit (`test/`)
- Repository: 정상 / 에러 / 캐시 hit 케이스
- `AuthInterceptor`의 401 → refresh → 재시도 흐름
- DTO 직렬화 round-trip

### 15.2 Widget (`test/`)
- Result 화면: tier별 (safe / warn / danger / unknown) 렌더링
- 로그인 폼: validation 에러 메시지
- `RiskBadge`, `RiskGauge` 골든 테스트(선택)

### 15.3 Integration (`integration_test/`)
- 로그인 → 홈 → 카메라(가짜 이미지 주입) → 결과 표시까지 happy path 1개
- emulator 기반, CI에서도 실행 가능하도록 시드 계정 활용

### 15.4 명령
```bash
flutter test                     # unit + widget
flutter test integration_test    # integration
```

---

## 16. CI / CD

- **GitHub Actions** matrix:
  - `os: [macos-latest]` (iOS 빌드 필요)
  - `target: [ios, android]`
- 단계: setup-flutter → `flutter pub get` → `dart format --set-exit-if-changed .` → `dart analyze` → `flutter test` → 빌드.
- **fastlane**:
  - iOS → **TestFlight** (internal group)
  - Android → **Play Internal Testing**
- 시크릿: signing key, fastlane match 비밀번호, App Store Connect API key는 GH Secrets로만 주입. 본 레포에 평문 금지.

---

## 17. 주요 패키지 (pubspec.yaml — 다음 작업자가 추가)

핵심:
- `flutter_riverpod`, `riverpod_annotation`
- `go_router`
- `dio`
- `freezed_annotation`, `json_annotation`
- `image_picker`, `camera`
- `image`, `flutter_image_compress`
- `fl_chart`
- `flutter_secure_storage`
- `hive`, `hive_flutter` (또는 `isar`, `isar_flutter_libs`)
- `shared_preferences`
- `firebase_core`, `firebase_messaging`
- `flutter_local_notifications`
- `connectivity_plus`
- `intl`
- `flutter_localizations` (sdk)

dev:
- `build_runner`
- `freezed`, `json_serializable`
- `riverpod_generator`
- `flutter_lints`
- `mocktail` (테스트)
- `integration_test` (sdk)

버전은 첫 `flutter pub add` 시점의 안정 버전으로 픽스. 메이저 업그레이드는 별도 PR로.

---

## 18. AI 작업 가이드라인

이 섹션은 본 앱에서 작업하는 AI 에이전트가 **반드시** 지킬 규칙이다.

### 18.1 구조 일관성
- 새 feature 추가 시 항상 `features/{name}/{data,domain,presentation}/` 3레이어를 만든다. 빈 레이어라도 `.gitkeep` 또는 placeholder 파일을 둔다.
- features 간 직접 import 금지. 공유 위젯은 `shared/widgets`, 공유 로직은 `core`로.

### 18.2 네트워크
- HTTP는 무조건 `core/api`에서 노출하는 `Dio` 또는 Repository를 통해서만. **features에서 `Dio()` 직접 생성 금지**.
- 새 엔드포인트는 Repository 메서드로 추가, presentation은 Repository만 의존.

### 18.3 코드 생성
- DTO(`@freezed`, `@JsonSerializable`) 또는 Provider(`@riverpod`)를 추가/변경했으면 즉시:
  ```bash
  dart run build_runner build --delete-conflicting-outputs
  ```
- 생성 파일(`*.g.dart`, `*.freezed.dart`)은 커밋 정책에 따른다(기본: 커밋).

### 18.4 토큰 / 비밀
- 토큰 저장은 **`flutter_secure_storage`만**. `shared_preferences`, hive, in-memory 캐시 단독 보관 금지.
- 어떤 시크릿도 코드/asset/git에 평문으로 두지 않는다. 빌드 시 `--dart-define`.

### 18.5 파일 삭제
- `rm` 사용 금지. **`trash <path>`**를 사용 (recoverable). 글로벌 hook이 강제한다.

### 18.6 의존 추가
- `flutter pub add <pkg>`로 추가하고, 본 CLAUDE.md §17 목록에 반영. 사유를 PR에 적는다.
- 무거운 패키지(>1MB native)는 PR에서 정당화 필요.

### 18.7 i18n
- 사용자에게 보이는 모든 문자열은 ARB 경유. `Text('확인')` 같은 하드코딩 금지.

### 18.8 접근성
- 새 인터랙티브 위젯은 `Semantics` 라벨 또는 `tooltip` 부착.
- 터치 타겟 48dp 이상 강제.

### 18.9 변경 후 검증
PR 전 로컬에서 다음을 통과시킨다:
```bash
dart format --set-exit-if-changed .
dart analyze
flutter test
flutter build apk --debug    # 또는 ios --no-codesign
```

---

## 19. PR 전 체크리스트

- [ ] `dart format .` 적용됨
- [ ] `dart analyze` 0 issues
- [ ] `flutter test` 전부 통과
- [ ] 신규/변경 feature에 widget 또는 unit 테스트 추가
- [ ] DTO 변경 시 `build_runner` 재실행 후 생성 파일 커밋
- [ ] 사용자 노출 문자열은 ARB에 등록
- [ ] iOS/Android 둘 다 디버그 빌드 통과
- [ ] 토큰/시크릿이 코드에 들어가지 않았는지 grep 확인
- [ ] §18 가이드라인 위반 없음

---

## 20. 알려진 미정 / TODO (다음 작업자에게 인수인계)

- [ ] `flutter create` 실제 실행 (§2)
- [ ] `pubspec.yaml`의 패키지 버전 픽스 (§17)
- [ ] hive vs isar 선택 확정 (§10)
- [ ] tier 색상 토큰 hex 확정 (§14) — 디자인 팀과
- [ ] Firebase 프로젝트 연결 (`google-services.json`, `GoogleService-Info.plist`) — 시크릿 관리 정책 결정 후
- [ ] iOS bundle id `kr.helpbee` 확정 / Android applicationId 일치
- [ ] fastlane 설정 디렉터리 (`ios/fastlane`, `android/fastlane`) 생성 — `flutter create` 이후
- [ ] 딥링크 도메인(Universal Links) 사용 여부 결정 (현재는 URL scheme만 가정)

---

본 문서는 cold-pickup 가이드다. 코드가 들어오기 시작하면 각 섹션을 코드와 동기화하고, 결정이 확정되면 "TODO" 섹션에서 제거한다.
