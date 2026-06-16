# HelpBee Mobile — 로컬 시뮬레이터 실행 가이드

> 이 문서는 `apps/mobile` Flutter 앱을 **본인 맥북에서 시뮬레이터로 띄우는** 방법입니다.
> 현재 구현 범위: **scaffold + 인증(스플래시 · 온보딩 · 로그인 · 회원가입 · 홈 placeholder)**.
> 검증: Flutter 3.38.6 / Dart 3.10, iOS 시뮬레이터 빌드 성공(`Runner.app`).

---

## 0. 준비 (최초 1회)

```bash
cd apps/mobile
flutter pub get          # 의존성
flutter gen-l10n         # 한국어 문자열(ARB → AppLocalizations) 생성
```

> ⚠️ `dart run build_runner ...`는 **돌리지 마세요.** 이 앱은 codegen(freezed/json/riverpod_generator)을
> 쓰지 않습니다(Dart 3.10 + 네이티브 build hook 비호환). DTO·상태·Provider 전부 수기 작성입니다.

---

## 1. 가장 빠른 길 — iOS 시뮬레이터 (권장, 이미 검증됨)

맥에 Xcode 26.2 + iPhone 16/17 시뮬레이터가 이미 있습니다.

```bash
# (1) 시뮬레이터 부팅 — 아무 iPhone 하나
open -a Simulator                      # 또는: xcrun simctl boot "iPhone 16"

# (2) 앱 실행 (백엔드 없이도 UI는 다 뜸 — 로그인 시도 시에만 서버 필요)
cd apps/mobile
flutter run -d iphone                  # 연결된 iOS 시뮬레이터로 실행
```

- 핫리로드: 실행 중 터미널에서 `r`(리로드) / `R`(리스타트) / `q`(종료).
- iOS 시뮬레이터는 호스트의 `localhost`를 그대로 공유 → 백엔드 주소가 `http://localhost:3001`이면 추가 설정 불필요.

### 백엔드에 실제로 붙여서 로그인/회원가입까지 테스트하려면

API 주소를 주입해서 실행합니다(기본값도 `localhost:3001`이라 보통 생략 가능):

```bash
flutter run -d iphone --dart-define=API_BASE=http://localhost:3001
```

백엔드를 같이 띄우는 법(모노레포 루트에서):

```bash
docker compose up -d postgres redis
# 마이그레이션 + API 서버 (필수 env는 docs/01-development/frontend-api-integration.md §9 참고)
pnpm --filter @helpbee/database migrate
JWT_SECRET=<64자+> REFRESH_TOKEN_PEPPER=<32자+> AI_BASE_URL=http://localhost:8000 \
AI_INTERNAL_HMAC_SECRET=<32자+> S3_IMAGES_BUCKET=helpbee-images-dev \
DATABASE_URL=postgresql://helpbee_user:helpbee_password@localhost:5432/helpbee \
REDIS_URL=redis://localhost:6379 CORS_ALLOWLIST=http://localhost:3000,http://localhost:3001 \
  pnpm --filter api dev
# 헬스: curl http://localhost:3001/health
```

> 참고(readiness §10): **회원가입 후 로그인은 바로 됩니다.** 단 이메일 인증 발송이 미구현이라
> 무료 사용자는 *분석* 단계에서만 막힙니다(이번 범위 밖). AI 분석/추론은 아직 동작 안 함.

---

## 2. Android 에뮬레이터로 돌리려면

현재 생성된 AVD가 없습니다. 한 번 만들어야 합니다.

```bash
flutter emulators                       # 목록 확인
flutter emulators --create --name pixel # AVD 생성(미설치 시 시스템 이미지 먼저 설치)
flutter emulators --launch pixel
# Android 에뮬레이터는 호스트를 10.0.2.2 로 봅니다 → API 주소를 그렇게 주입
flutter run -d emulator --dart-define=API_BASE=http://10.0.2.2:3001
```

---

## 3. 빠른 확인(빌드/테스트만)

```bash
flutter analyze        # 정적 분석 (현재 0 issues)
flutter test           # 위젯 테스트 (현재 3 passing)
flutter build ios --simulator --debug --no-codesign   # 풀 컴파일 검증(약 1~2분)
```

---

## 4. 화면 흐름 (이번 구현)

```
Splash → (최초 실행) Onboarding 3p → Login ⇄ Signup → Home(placeholder, 로그아웃)
                     (재실행/세션 있음) → 토큰 복원 → Home
```

- 토큰: access는 메모리, refresh는 `flutter_secure_storage`. 401(만료) 시 자동 refresh 후 1회 재시도(single-flight).
- SNS 로그인 버튼은 디자인 반영용 **비활성(준비 중)** — 백엔드에 SNS 없음.
- 아이디/비밀번호 찾기 링크도 "준비 중" — 백엔드 미구현.

---

## 5. 자주 막히는 곳

| 증상 | 해결 |
|---|---|
| `flutter run`에 기기 안 잡힘 | 시뮬레이터 먼저 부팅(`open -a Simulator`) 후 `flutter devices` 확인 |
| 한국어 문자열이 비어 보임 | `flutter gen-l10n` 다시 실행 |
| 폰트(Jua)가 처음에 안 보임 | `google_fonts`가 최초 1회 네트워크로 받음. 오프라인이면 폴백 폰트로 렌더(추후 번들 예정) |
| 로그인 시 네트워크 오류 | 백엔드(`localhost:3001`) 떠 있는지 / Android면 `10.0.2.2` 썼는지 확인 |
| iOS 빌드 느림(첫 회) | 최초 `pod install` + Xcode 빌드라 1~2분 소요. 이후 캐시됨 |
