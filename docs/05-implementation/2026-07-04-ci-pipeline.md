# 2026-07-04 — 첫 GitHub Actions CI 파이프라인 (P2-2)

> PR #38 (예정) · 브랜치 `feature/ci-pipeline` (off develop)
> 산출물: `.github/workflows/ci.yml`

## 목표

HelpBee 모노레포의 **첫 CI**. `.github/workflows/` 는 이전까지 존재하지 않았다.
원칙: **첫 develop 실행에서 GREEN** — 워크플로에 넣은 모든 명령을 이 브랜치에서 로컬로
먼저 실행해 통과를 확인한 것만 포함한다. 로컬에서 깨지면 (a) 사소한 설정이면 고치고,
(b) 아니면 제외하고 사유를 여기 기록한다.

## 트리거 / 공통

- `pull_request` → `develop`, `main` + `push` → `develop`
- `paths-ignore: ['**.md', '.env.example']` (문서/예제 변경은 스킵)
  - ⚠️ 후속: branch protection 에서 이 체크를 **required** 로 걸 경우, 마크다운-only PR 은
    체크가 아예 리포트되지 않아 머지가 막힐 수 있음(GitHub 알려진 함정). required 설정 시
    재검토(더미 잡 또는 paths-ignore 제거).
- `concurrency` + `cancel-in-progress` — 같은 ref 새 커밋이 오면 진행 중 실행 취소.

## 잡 구성 (3개, 모두 ubuntu-latest)

### 1. `node` — type-check + api test
- pnpm/action-setup@v4 (version 10, 로컬 10.20 / lockfile 9.0 호환) → setup-node@v4
  (node 22, `cache: pnpm`) → `pnpm install --frozen-lockfile`.
- 실행: `pnpm --filter` 로 **명시적 개별 실행** (blanket `turbo run` 회피 — 아래 제외 사유).
  - `@helpbee/types` type-check
  - `@helpbee/database` type-check
  - `@helpbee/api` type-check
  - `@helpbee/api` test (vitest, 166 tests)

### 2. `ai` — pytest
- setup-python@v5 (**3.10**, 로컬 .venv 와 동일, `cache: pip`) →
  `pip install -r requirements-dev.txt` → `pytest -q`.
- `requirements-dev.txt` 가 `-r requirements.txt` + `pytest==9.0.3` + `pytest-asyncio==1.4.0`.
- `requirements.txt` 는 **CPU 전용**(torch 없음) — fastapi/pydantic/openai/pillow/onnxruntime/
  numpy(<2)/boto3. 무거운 torch·ultralytics 는 `requirements-gpu.txt`(학습용)라 CI 미포함.

### 3. `mobile` — flutter analyze + test
- subosito/flutter-action@v2 (flutter-version **3.38.6**, channel stable, cache) →
  `flutter pub get` → `flutter analyze` → `flutter test`.

## 로컬 선검증 결과 (이 브랜치, develop 기준)

| CI 명령 | 결과 |
|---|---|
| `pnpm install --frozen-lockfile` | ✅ PASS |
| `@helpbee/types` type-check | ✅ PASS |
| `@helpbee/database` type-check | ✅ PASS |
| `@helpbee/api` type-check | ✅ PASS |
| `@helpbee/api` test (vitest) | ✅ PASS (16 files / 166 tests, <1s) |
| `ai` `pytest -q` (.venv) | ✅ PASS (65 passed, 0.78s) |
| `mobile` `flutter analyze` | ✅ PASS (No issues found) |
| `mobile` `flutter test` | ⚠️ 로컬 실패(macOS 전용 원인) — CI 미검증, 아래 참조 |

## 제외한 스텝과 사유 (develop 기준 실제 실패/미설정)

- **lint (전 워크스페이스)** — 제외.
  - `apps/api` 의 `lint`(`eslint src`)는 **eslint 미설치**(`sh: eslint: command not found`).
    루트/워크스페이스 어디에도 eslint 설치 없음.
  - `apps/admin`·`apps/web` 의 `lint`(`next lint`)는 **eslintrc 부재** — 최초 실행 시
    대화형 프롬프트로 멈춤(비-TTY CI 에서 hang/fail 위험). 그래서 blanket `turbo run lint`
    대신 명시적 필터만 사용.
- **`@helpbee/ui` type-check** — 제외. **tsconfig.json 부재**(typescript devDep 은 있음).
  `tsc --noEmit` 이 입력 프로젝트 못 찾고 usage 출력 후 exit 1.
- **`@helpbee/admin` / `@helpbee/web` type-check** — 제외. 공유 `@helpbee/config/typescript/
  nextjs.json` 설정이 깨져 있음:
  - admin: `TS5070 Option '--resolveJsonModule' cannot be specified when 'moduleResolution'
    is set to 'classic'`.
  - web: 위 + `TS5103 Invalid value for '--ignoreDeprecations'`.
  - 두 앱 모두 현재 `src/` 가 `.gitkeep` 스켈레톤(실 소스 0) — 고쳐도 검증 대상 없음.
    tsconfig 프리셋 수정은 CI 범위 밖이라 미터치(후속 과제로 분리).
- **`@helpbee/database` test** — 제외. `test:integration` 은 `DB_ITEST=1` + 실 Postgres 필요.
  일반 `test` 스크립트 없음. (서비스 컨테이너 미도입 — 아래 findings 참조)
- **`dart format --set-exit-if-changed`** — 제외. develop 기준 **84개 중 47개 미포맷**이라
  즉시 실패. (`--output=none` 으로 확인, 디스크 변경 없음.) 포맷 정리는 별도 PR 과제.

## Findings (팀 참고)

- **api 테스트는 DB/Redis 서비스 컨테이너 불필요.** 테스트 파일 전수 grep 결과 실제
  postgres/ioredis 연결 없음(전부 in-process/mock). `config/env.ts` 는 fail-fast 지만
  테스트가 `loadEnv(process.env)` 를 부팅 경로로 타지 않음 → **주입한 env 변수 0개**.
  따라서 node 잡에 서비스 컨테이너/시크릿 불필요.
- **주입 env 변수: 없음** (node/ai 모두). ai 도 순수 단위테스트라 OPENAI_API_KEY 등 불요.
- **python 버전 결정: 3.10** (로컬 .venv 3.10.4 와 일치, 리스크 최소화). deps 는
  requirements-dev.txt 서브셋(=CPU requirements + pytest 2종). torch 미포함이라 설치 가볍고
  pip 캐시로 추가 단축.
- **format-clean 상태: NOT clean** (mobile 47/84 미포맷). → dart format 게이트 제외 근거.
- pnpm lockfile v9.0 ↔ action-setup pnpm 10 핀. node 22(engines `>=18`, 로컬 22).

## YAML 검증

- `python -c "import yaml; yaml.safe_load(...)"` → **YAML OK**.
- `actionlint` — 로컬 미설치라 미실행(설치 안 함). 액션 핀/구문은 수동 검토.

## CI 미검증 목록 (실제 GH 실행만이 증명 가능)

- **`mobile` `flutter test`** — 로컬(macOS) 실패는 오직 `objective_c-9.4.1` 패키지의
  **darwin 네이티브-에셋 빌드 훅**이 `xcrun`(Xcode 라이선스 미동의) 을 호출해 죽는 것.
  ubuntu 러너에선 이 darwin 훅이 빌드되지 않아 통과 예상 — 그러나 **미검증**.
  (만약 CI 에서 여기서 깨지면: 임시로 `flutter test` 스텝만 제거하고 analyze 만 유지 권장.)
- **linux 러너 동작 전반** — 로컬은 macOS/Node22/pnpm10/py3.10. 러너 OS 차이로 인한
  경로/도구 차이는 첫 실행에서만 확정.
- **서비스 컨테이너** — 이번엔 사용 안 함(불필요 확인). 향후 db 통합테스트 도입 시 추가.
- **actions 자체**(pnpm/action-setup, setup-node/python cache, subosito/flutter-action)의
  네트워크 의존 동작.

## 예상 CI 소요 (러너 기준 추정)

- `node`: ~1.5–3분 (pnpm install 캐시 후 + tsc 3회 + vitest <1s).
- `ai`: ~1–2분 (pip install onnxruntime/numpy 휠 + pytest <1s; pip 캐시 후 단축).
- `mobile`: ~3–6분 (flutter SDK 캐시 miss 시 SDK 다운로드가 지배적; cache hit 시 ~2분).
- 3잡 병렬이라 벽시계 **≈ mobile 잡 시간(대략 3–6분)**.

## 후속 과제 (이 PR 범위 밖)

1. `@helpbee/config/typescript/nextjs.json` moduleResolution/ignoreDeprecations 수정 →
   admin/web type-check 복구.
2. eslint + flat config 도입(루트 공유) → lint 게이트 추가.
3. `packages/ui/tsconfig.json` 추가 → ui type-check 복구.
4. `dart format .` 일괄 적용 후 format 게이트 추가.
5. branch protection required-checks 설정 시 paths-ignore 함정 재검토.
