# CLAUDE.md

> **Level: Enterprise** | Initialized: 2026-04-09 | bkit v2.1.1

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 🎯 프로젝트 개요

**HelpBee**: AI 기반 스마트 양봉 진단 SaaS 플랫폼

- **목표**: 2025년 6월 MVP 출시
- **고객**: 한국의 중형 양봉가 (200~500통)
- **핵심 가치**: 벌통 이미지 → AI 분석 → 바로아 응애 감염 진단 리포트
- **기술**: 모노레포 (Turborepo), 풀스택 (Next.js, Hono, FastAPI)

---

## 📁 모노레포 구조 이해

### 전체 아키텍처

이것은 **Turborepo 모노레포**입니다. 단일 Git 저장소에서 4개의 독립적 앱 + 4개의 공유 패키지를 관리합니다.

```
┌─────────────────────────────────────────────────┐
│  User Browser                                   │
├─────────────────────────────────────────────────┤
│  apps/web              apps/admin              │
│  (Next.js 사용자웹)    (Next.js 관리자)        │
└────────────────┬─────────────────────────────┘
                 │
    ┌────────────▼────────────┐
    │  apps/api (Hono.js)    │
    │  핵심 비즈니스 로직     │
    ├────────────┬───────────┤
    │            │           │
    ▼            ▼           ▼
  PostgreSQL  Redis   apps/ai (FastAPI)
              ↓              ↓
         @helpbee/      OpenAI API
         database

공유 패키지:
├─ @helpbee/types (타입)
├─ @helpbee/ui (컴포넌트)
├─ @helpbee/database (DB 스키마)
└─ @helpbee/config (설정)
```

### 각 앱의 역할

| 앱 | 기술 | 역할 | 포트 |
|---|---|---|---|
| **web** | Next.js 14+ | 양봉가 웹앱 (벌통 등록, 이미지 업로드, 결과 조회) | 3000 |
| **admin** | Next.js 14+ | 관리자 대시보드 (사용자/구독 관리, 분석 모니터링) | 3002 |
| **api** | Hono.js | API 서버 (인증, CRUD, 이미지 업로드 조율) | 3001 |
| **ai** | FastAPI | AI 분석 서버 (OpenAI Vision API 호출) | 8000 |

---

## 📖 참고 문서 가이드

### 반드시 읽을 문서

1. **@PROJECT_STRUCTURE.md** (구조 파악 시)
   - 각 앱/패키지의 상세 구조
   - 서비스 간 데이터 흐름
   - 의존성 관계도
   - 향후 구현 단계

2. **@gitworkflow.md** (개발/배포 시)
   - Git 브랜칭 전략 (feature, bugfix, release 등)
   - GitHub Actions 워크플로우 정의
   - 배포 환경 (staging, production)
   - PR 체크리스트

3. **@README_MONOREPO.md** (빠른 시작)
   - 설치 및 실행 방법
   - 개별 앱 실행 명령어
   - 데이터베이스 마이그레이션

---

## 🚀 자주 사용하는 명령어

### 환경 설정

```bash
# 의존성 설치 (첫 실행 시)
pnpm install

# 환경변수 설정
cp .env.example .env.local
# 필수: DATABASE_URL, REDIS_URL, OPENAI_API_KEY, JWT_SECRET 입력

# DB & Redis 시작 (Docker 필요)
docker-compose up -d
```

### 개발 서버

```bash
# 전체 앱 동시 실행 (권장)
pnpm dev

# 개별 앱 실행
pnpm --filter @helpbee/web dev      # 웹앱
pnpm --filter @helpbee/admin dev    # 관리자
pnpm --filter @helpbee/api dev      # API 서버
cd apps/ai && python -m uvicorn app.main:app --reload  # AI 서버
```

### 빌드 & 린트

```bash
# 전체 빌드
pnpm build

# 린트 확인
pnpm lint

# 타입 체크
pnpm type-check

# 테스트
pnpm test

# 특정 앱만 빌드
pnpm --filter @helpbee/api build
```

### 데이터베이스

```bash
# DB 스키마 변경 후 마이그레이션 생성
pnpm --filter @helpbee/database push

# 마이그레이션 적용
pnpm --filter @helpbee/database migrate

# Drizzle Studio (웹 UI로 DB 관리)
pnpm --filter @helpbee/database studio
```

### 정리

```bash
# 빌드 결과, .next, dist 등 정리
pnpm clean

# node_modules 완전 제거 후 재설치 (문제 해결 시)
pnpm clean && pnpm install
```

---

## 🔄 개발 워크플로우

### 새 기능 개발 시

1. **@gitworkflow.md 확인**: 브랜칭 전략 참고
   ```bash
   git checkout -b feature/my-feature
   ```

2. **로컬 개발**
   ```bash
   pnpm dev  # 필요한 서비스 실행
   ```

3. **커밋 & PR**
   - develop 브랜치로 PR 생성
   - CI 자동 실행 (린트, 테스트)
   - 최소 1명 승인 필수

4. **머지 & 배포**
   - develop에 머지되면 자동 테스트
   - 정기 릴리스 시 main으로 release PR 생성
   - 배포 자동화

---

## 💡 핵심 기술 결정사항

### 왜 이 기술을 선택했는가?

| 기술 | 선택 이유 |
|---|---|
| **Turborepo** | 빠른 캐싱, 변경된 패키지만 빌드 |
| **Next.js 14** | SSR/SSG, 이미지 최적화, API 라우트 |
| **Hono.js** | Express 대비 5~10배 빠름, TypeScript 네이티브 |
| **FastAPI** | OpenAI SDK 생태계, 이미지 처리 (Pillow) |
| **Drizzle ORM** | Prisma보다 런타임 오버헤드 없음, 타입 안전 |
| **pnpm** | Yarn/npm보다 저장 공간 효율적, 속도 빠름 |

---

## 🤖 AI/ML 도구 활용

### Claude 플러그인과 스킬 자유로운 사용

이 프로젝트에서 다음 도구들을 적극 활용하세요:

#### 플러그인 (Plugin)
- **@figma** - UI 디자인이 필요하면 Figma 연동
- **@game-changing-features** - 10x 기능 발상

#### 스킬 (Skill)
- **@update-config** - 설정 파일 수정
- **@keybindings-help** - 개발 생산성 향상
- **@simplify** - 코드 정리 및 최적화
- **@humanizer** - 문서 작성 시 자연스럽게

#### 명령어
- `/help` - Claude Code 사용법
- `/model` - 모델 변경
- `/fast` - 빠른 응답 (속도 vs 정확도)

---

## 🔧 주요 파일 경로

```
프로젝트 루트/
├── CLAUDE.md              👈 현재 파일 (가이드)
├── PROJECT_STRUCTURE.md   👈 상세 구조 (필독)
├── gitworkflow.md         👈 워크플로우 (필독)
├── README_MONOREPO.md     👈 빠른 시작 (필독)
│
├── apps/
│   ├── web/               → 사용자 웹앱
│   ├── admin/             → 관리자 대시보드
│   ├── api/src/           → API 서버 로직
│   └── ai/app/            → AI 분석 로직
│
├── packages/
│   ├── types/src/         → 공유 타입
│   ├── database/src/schema/ → DB 스키마
│   ├── ui/src/            → UI 컴포넌트
│   └── config/            → 설정
│
├── .github/workflows/     → CI/CD (구현 예정)
├── infra/docker/          → Docker 설정
│
└── 루트 설정
    ├── package.json       → 모노레포 설정
    ├── turbo.json         → 빌드 파이프라인
    ├── pnpm-workspace.yaml → 워크스페이스
    └── docker-compose.yml → 로컬 개발 환경
```

---

## 🎓 개발 시 주의사항

### 타입 안전성
- 모든 코드는 TypeScript로 작성 (Python 제외)
- `@helpbee/types` 패키지의 타입을 우선 사용
- 새 타입 추가 시 `packages/types/src/`에 추가

### 모노레포 의존성
- 앱 간 의존성은 패키지 경유로만 가능
- 직접 `import`하지 않음 (예: `import from '@helpbee/types'`)
- 순환 의존성 금지

### API 문서화
- 새 엔드포인트는 주석으로 설명
- request/response 타입 명시

### 환경변수
- `.env.example`에 필수 변수 추가
- `.env.local`에 실제 값 입력 (git 커밋 X)

---

## 🆘 문제 해결

### 의존성 문제
```bash
# node_modules 캐시 문제 시
pnpm clean && pnpm install
```

### 포트 충돌
```bash
# 이미 사용 중인 포트 확인 및 종료
lsof -i :3000   # web
lsof -i :3001   # api
lsof -i :8000   # ai
```

### DB 연결 문제
```bash
# Docker 서비스 상태 확인
docker-compose ps

# 재시작
docker-compose restart
```

---

## 📞 연락 & 문서 링크

- **GitHub**: https://github.com/hyunshu12/HelpBee
- **이슈**: GitHub Issues로 보고
- **문서**: 각 파일의 주석과 README 참고

---

## ✅ 다음 단계

- [ ] @PROJECT_STRUCTURE.md 읽기
- [ ] @gitworkflow.md 확인
- [ ] `pnpm dev`로 로컬 환경 실행
- [ ] 개발 시작!

