# HelpBee Mobile — 로컬 실행 가이드 (기초 세팅)

> `apps/mobile` Flutter 앱을 **맥북 시뮬레이터/기기에서 끝까지 동작**시키는 방법.
> 현재 구현 범위: **로그인 → 벌통 CRUD(등록/수정/삭제) → 촬영 → 사진 검토 → 분석중 → 진단 레포트** 전체.
> 검증 환경: Flutter 3.38 / Dart 3.10, iOS 시뮬레이터 빌드 성공 · `flutter test` 30 통과 · 백엔드 라이브 E2E(presign→S3→confirm→analyses=success).

---

## TL;DR (이 맥북, 이미 셋업됨)

```bash
# 1) 인프라 (brew 서비스, 보통 이미 떠 있음)
brew services start postgresql@16 && brew services start redis

# 2) 백엔드 API (apps/api/.env 자동 로드) — 터미널 A
pnpm --filter api dev                     # http://localhost:3001/health

# 3) AI 추론 서버 (apps/ai/.env 로드) — 터미널 B
cd apps/ai && source .venv/bin/activate \
  && set -a && source .env && set +a \
  && uvicorn app.main:app --host 0.0.0.0 --port 8000   # http://localhost:8000/health

# 4) 모바일 — 터미널 C
cd apps/mobile && flutter run -d iphone   # 시뮬레이터 먼저: open -a Simulator
```

**시드 로그인**: `beekeeper1@helpbee.local` / `helpbee-dev-2026` (이메일 인증 완료 상태라 분석까지 가능).

> ⚠️ `.env` 파일들은 **git에 없습니다(gitignored)**. 이 맥북엔 이미 있습니다. 새 머신은 아래 **부록 A** 참고.
> ⚠️ `dart run build_runner ...` **금지** — 이 앱은 codegen 미사용(Dart 3.10 build-hook 비호환). DTO·Provider 수기 작성. `dart format` 전체 실행도 금지(레포가 old-style이라 churn 발생).

---

## 0. 사전 준비 (최초 1회)

```bash
cd apps/mobile
flutter pub get          # 의존성 (camera/image_picker/flutter_image_compress 포함)
flutter gen-l10n         # 한국어 문자열(ARB → AppLocalizations) 생성
```

데이터베이스(최초 1회, 모노레포 루트에서):
```bash
brew services start postgresql@16 redis
pnpm --filter @helpbee/database migrate        # 스키마 적용
pnpm --filter @helpbee/database tsx src/seeds/dev.ts   # 시드(시드 계정 생성)
```

---

## 1. 백엔드 띄우기 (분석까지 테스트하려면 필수)

### 1-1. API 서버 (Hono, :3001)
```bash
pnpm --filter api dev          # apps/api/.env 로드 (tsx watch)
curl http://localhost:3001/health   # {"status":"ok"}
```
필수 env(이미 `apps/api/.env`에 설정됨): `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `REFRESH_TOKEN_PEPPER`,
`AI_BASE_URL=http://localhost:8000`, `AI_INTERNAL_HMAC_SECRET`(AI와 동일값), `S3_IMAGES_BUCKET=helpbee-images-dev`,
`AWS_REGION=ap-northeast-2`, `CORS_ALLOWLIST`. (상세: `docs/01-development/frontend-api-integration.md` §9)

### 1-2. AI 추론 서버 (FastAPI, :8000)
```bash
cd apps/ai
python -m venv .venv && source .venv/bin/activate   # 최초 1회
pip install -r requirements.txt                     # 최초 1회 (CPU/ONNX)
set -a && source .env && set +a                     # apps/ai/.env 로드
uvicorn app.main:app --host 0.0.0.0 --port 8000
curl http://localhost:8000/health                   # {"status":"ok"}
```
- 추론은 **CPU ONNX**(`best.onnx`, ~36MB)를 사용. 부팅 시 `~/.cache/helpbee/yolo/`에 없으면 S3(`helpbee-models`)에서 받음 → AWS 자격증명 필요(부록 A).
- 무료 사용자 분석 엔진 = `yolo`(OpenAI 키 불필요). `AI_INTERNAL_HMAC_SECRET`은 **api와 ai가 동일해야** 함.

---

## 2. 모바일 실행

```bash
open -a Simulator                       # iOS 시뮬레이터 부팅 (아무 iPhone)
cd apps/mobile
flutter run -d iphone                   # 기본 API_BASE=http://localhost:3001
```
- 다른 API 주소: `flutter run -d iphone --dart-define=API_BASE=http://localhost:3001`
- **Android 에뮬레이터**는 호스트를 `10.0.2.2`로 봄: `flutter run -d emulator --dart-define=API_BASE=http://10.0.2.2:3001`
- 핫리로드: `r`(리로드) / `R`(리스타트) / `q`(종료).

### 카메라 주의
- **iOS 시뮬레이터에는 카메라가 없음** → 촬영 화면이 "갤러리 사용" 폴백을 안내. **갤러리 버튼**으로 사진을 골라 분석 흐름을 끝까지 테스트.
- 실제 카메라 촬영은 **실기기**에서. (권한: iOS `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription`, Android `CAMERA` 이미 설정됨)

---

## 3. 빠른 확인 (빌드/테스트만, 백엔드 불필요)

```bash
cd apps/mobile
flutter analyze        # 0 issues
flutter test           # 30 passing
flutter build ios --simulator --no-codesign   # 풀 컴파일 (첫 회 pod install 1~2분)
```

---

## 4. 화면 흐름 (현재 구현 전체)

```
Splash → (최초) Onboarding 3p → Login ⇄ Signup
       → Home(양봉장 현황: 쿼터 배너 + 벌통 카드 + 진단하기 FAB, 상단 + 벌통 등록)
            ├ 벌통 등록(풀스크린: 이름*/위치/설치일*/메모)
            ├ 벌통 상세(위험 요약·위치·이력 타임라인·⋮수정/삭제·다시 촬영)
            └ 진단하기 → 촬영할 벌통 선택 → 카메라 → 사진 검토 → 분석중 → 레포트(게이지·권장조치)
       하단 탭: 벌통 / 진단 이력 / 설정(프로필·테마·로그아웃)
```

---

## 5. 자주 막히는 곳

| 증상 | 해결 |
|---|---|
| 로그인 시 네트워크 오류 | API(`:3001`) 떠 있나 / Android면 `10.0.2.2` 썼나 |
| 분석이 "분석 실패"로 끝남 | AI 서버(`:8000`) 떠 있나 / `AI_INTERNAL_HMAC_SECRET`가 api·ai 동일한가 / 모델(`best.onnx`) 받았나 |
| 분석이 403(이메일 인증) | 무료 사용자 이메일 미인증. 시드 계정은 인증됨. 직접 만든 계정은 DB `users.email_verified_at` set |
| 시뮬레이터에서 촬영 안 됨 | 정상(카메라 없음) → 갤러리 버튼 사용 |
| 기기 안 잡힘 | `open -a Simulator` 후 `flutter devices` |
| 한국어가 비어 보임 | `flutter gen-l10n` 재실행 |
| DB/시드 오류 | `brew services list`로 PG/Redis 확인 → `pnpm --filter @helpbee/database migrate` |

---

## 6. 정리 / 종료

```bash
# 개발 서버 종료 (포트로 kill)
for p in 3001 8000; do kill $(lsof -nP -iTCP:$p -sTCP:LISTEN -t) 2>/dev/null; done
# brew 서비스는 그대로 둬도 무방 (필요 시)
brew services stop postgresql@16 redis
```

---

## 부록 A. 새 머신에서 처음 셋업할 때

`.env` 파일들은 git에 없으므로 직접 만들어야 합니다.

1. **인프라**: `brew install postgresql@16 redis` → `brew services start ...` (Docker 미사용).
   DB: `createdb helpbee` + 롤/비번은 `docker-compose.yml` 기본값(`helpbee_user`/`helpbee_password`)에 맞춤.
2. **apps/api/.env**: 위 §1-1 변수. 시크릿은 임의 생성(`openssl rand -hex 32`). `AI_INTERNAL_HMAC_SECRET`은 ai와 동일하게.
3. **apps/ai/.env**: `AI_INTERNAL_HMAC_SECRET`(api와 동일), `YOLO_MODEL_VERSION=v0.1.0`, `AWS_S3_MODELS_BUCKET=helpbee-models`,
   `AWS_REGION=ap-northeast-2`, `YOLO_CACHE_DIR=~/.cache/helpbee/yolo`, `IMAGE_ALLOWLIST_HOSTS=s3.ap-northeast-2.amazonaws.com,cdn.helpbee.kr`.
4. **AWS 자격증명**: 모델/이미지 S3 접근용. IAM 사용자(region `ap-northeast-2`)로 `aws configure`. S3 이미지 버킷 `helpbee-images-dev` 필요.
5. `pnpm install` → DB migrate + seed → §1·§2 순서로 기동.

> 시드 비밀번호는 개발 전용. 자세한 백엔드 계약/에러코드/토큰 정책은 `docs/01-development/frontend-api-integration.md`.
