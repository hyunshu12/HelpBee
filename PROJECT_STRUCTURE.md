# HelpBee 프로젝트 구조 가이드 (클로드용)

## 프로젝트 개요

**HelpBee**는 AI 기반 스마트 양봉 진단 SaaS 플랫폼의 모노레포입니다.
- **타겟 고객**: 한국의 중형 양봉가
- **런칭 목표**: 2025년 6월
- **핵심 기능**: 벌통 이미지 AI 분석 → 바로아 응애 감염 진단 → 리포트 생성

## 🏗 전체 아키텍처

```
사용자 브라우저
    ↓
    ├─► [apps/web] (Next.js 사용자 웹)
    └─► [apps/admin] (Next.js 관리자 대시보드)
         ↓
    [apps/api] (Hono.js API 서버) ───┬─► PostgreSQL [packages/database]
         ↓                           ├─► Redis
         └─────► [apps/ai] (FastAPI AI 분석)
                      ↓
                 OpenAI Vision API (외부)
```

---

## 📁 디렉토리 상세 가이드

### 루트 레벨 설정 파일

| 파일 | 목적 |
|---|---|
| `package.json` | 모노레포 루트 설정, 공통 스크립트 |
| `turbo.json` | Turborepo 파이프라인 정의 |
| `pnpm-workspace.yaml` | pnpm 워크스페이스 구성 |
| `.gitignore` | Git 무시 목록 |
| `.env.example` | 환경변수 템플릿 |
| `docker-compose.yml` | 로컬 DB/Redis 구성 |

### apps/ - 메인 애플리케이션

#### `apps/web/` - 사용자 웹앱
- **프레임워크**: Next.js 14+ (App Router)
- **목적**: 양봉가가 벌통 이미지를 업로드하고 분석 결과를 확인하는 곳
- **주요 기능**:
  - 로그인/회원가입
  - 벌통 등록 및 관리
  - 이미지 업로드
  - 분석 결과 대시보드
  - 리포트 조회
  - 구독 관리

**구조**:
```
apps/web/
├── app/              # Next.js App Router
│   ├── (auth)/       # 인증 라우트
│   ├── (dashboard)/  # 대시보드 라우트
│   │   ├── dashboard/
│   │   ├── hives/
│   │   ├── reports/
│   │   └── settings/
│   └── api/          # Next.js Route Handlers
├── components/       # React 컴포넌트
├── lib/              # 유틸리티 (API 클라이언트 등)
├── public/           # 정적 파일
├── package.json
├── tsconfig.json
└── next.config.js
```

#### `apps/admin/` - 관리자 대시보드
- **프레임워크**: Next.js 14+ (App Router)
- **목적**: 관리자가 서비스를 모니터링하고 운영하는 곳
- **주요 기능**:
  - 사용자 관리
  - 구독 관리
  - AI 분석 로그 모니터링
  - 서비스 통계 및 분석

**구조**:
```
apps/admin/
├── app/
│   ├── (auth)/
│   └── (dashboard)/
│       ├── users/
│       ├── subscriptions/
│       ├── analyses/
│       ├── ai-logs/
│       └── stats/
├── components/
├── package.json
└── tsconfig.json
```

#### `apps/api/` - API 서버
- **프레임워크**: Hono.js (초경량 Node.js 프레임워크)
- **목적**: 웹과 AI 서버 사이의 중개 역할, 비즈니스 로직 처리
- **주요 기능**:
  - 사용자 인증 (JWT)
  - 벌통 CRUD
  - 분석 요청/조회
  - 이미지 업로드 (S3 Presigned URL)
  - 리포트 생성/조회
  - 구독 관리
  - Rate limiting, 에러 처리

**구조**:
```
apps/api/
├── src/
│   ├── index.ts          # 메인 진입점
│   ├── routes/
│   │   ├── auth.ts       # /api/auth
│   │   ├── hives.ts      # /api/hives
│   │   ├── analyses.ts   # /api/analyses
│   │   ├── reports.ts    # /api/reports
│   │   ├── subscriptions.ts
│   │   └── admin/        # 관리자 API
│   ├── middleware/
│   │   ├── auth.ts       # JWT 검증
│   │   ├── rate-limit.ts # 요청 제한
│   │   └── upload.ts     # 이미지 업로드 처리
│   ├── services/
│   │   ├── hive.service.ts       # 벌통 비즈니스 로직
│   │   ├── analysis.service.ts   # AI 분석 조율
│   │   ├── storage.service.ts    # S3 관리
│   │   └── notification.service.ts
│   └── db/
│       └── index.ts      # Drizzle 인스턴스
├── package.json
├── tsconfig.json
└── Dockerfile
```

#### `apps/ai/` - AI 분석 서버
- **언어**: Python 3.10+
- **프레임워크**: FastAPI
- **목적**: OpenAI Vision API를 이용한 벌통 이미지 분석
- **주요 기능**:
  - 바로아 응애 탐지
  - 감염 위험도 계산
  - 분석 결과 JSON 반환
  - 로깅 및 모니터링

**구조**:
```
apps/ai/
├── app/
│   ├── main.py           # FastAPI 앱
│   ├── routers/
│   │   ├── analyze.py    # /api/analyze 엔드포인트
│   │   └── health.py     # 헬스 체크
│   ├── services/
│   │   ├── openai_service.py    # OpenAI API 호출
│   │   ├── image_service.py     # 이미지 전처리
│   │   └── report_service.py    # 분석 결과 가공
│   ├── models/
│   │   ├── request.py    # Pydantic 요청 모델
│   │   └── response.py   # Pydantic 응답 모델
│   └── prompts/
│       └── varroa_analysis.py  # OpenAI 프롬프트
├── requirements.txt
├── Dockerfile
└── package.json (메타데이터만)
```

### packages/ - 공유 라이브러리

#### `packages/types/` - TypeScript 타입
- **목적**: 모든 서비스가 사용하는 공통 타입 정의
- **주요 타입**:
  - `User` - 사용자
  - `Hive` - 벌통
  - `AnalysisResult` - AI 분석 결과
  - `Report` - 분석 리포트
  - `Subscription` - 구독 정보

```typescript
// 예: packages/types/src/index.ts
export interface Hive {
  id: string;
  userId: string;
  name: string;
  location: string;
  createdAt: Date;
  updatedAt: Date;
}
```

#### `packages/ui/` - 공유 UI 컴포넌트
- **기반**: shadcn/ui (Tailwind CSS)
- **목적**: 웹과 관리자 대시보드에서 재사용할 UI 컴포넌트
- **포함 예정 컴포넌트**:
  - Button, Card, Modal
  - Chart (분석 결과 시각화)
  - Form components
  - DataTable

#### `packages/database/` - DB 스키마 & ORM
- **ORM**: Drizzle ORM
- **목적**: PostgreSQL 스키마 관리, 마이그레이션
- **구조**:
  ```
  packages/database/
  ├── src/
  │   ├── schema/
  │   │   ├── users.ts
  │   │   ├── hives.ts
  │   │   ├── analyses.ts
  │   │   ├── reports.ts
  │   │   └── subscriptions.ts
  │   └── index.ts (db 인스턴스 내보내기)
  ├── migrations/    (Drizzle이 자동 생성)
  └── drizzle.config.ts
  ```

#### `packages/config/` - 공유 설정
- **포함**:
  - `typescript/` - tsconfig.json
    - `base.json` - 기본 설정
    - `nextjs.json` - Next.js용 확장
    - `node.json` - Node.js용 확장
  - `eslint/` - ESLint 설정 (향후)

### infra/ - 배포 & 인프라

#### `infra/docker/`
- `docker-compose.yml` - 로컬 개발 환경 (PostgreSQL, Redis)
- `nginx/nginx.conf` - 리버스 프록시 설정 (프로덕션)

#### `infra/scripts/`
- `setup.sh` - 초기 환경 설정
- `migrate.sh` - DB 마이그레이션 스크립트

### `.github/workflows/` - CI/CD
- `ci.yml` - PR 시 자동 빌드/린트
- `deploy.yml` - main 브랜치 자동 배포 (향후)

---

## 🔄 서비스 간 데이터 흐름

### 1️⃣ 이미지 업로드 흐름

```
사용자 웹 (web)
    ↓
API 서버 /api/hives/:id/upload
    ↓
S3 Presigned URL 발급
    ↓
클라이언트 → S3 직접 업로드 (서버 부하 없음)
    ↓
클라이언트 → API 서버 /api/analyses (분석 요청)
    ↓
API 서버 → AI 서버 (S3 이미지 URL 전달)
    ↓
AI 서버 → OpenAI Vision API (이미지 분석)
    ↓
분석 결과 → API 서버 → DB 저장
    ↓
웹 대시보드 표시
```

### 2️⃣ 데이터 조회 흐름

```
웹/관리자 → API 서버 (JWT 인증)
         ↓
API 서버 (Redis 캐싱 확인)
         ↓
캐시 없음 → DB (PostgreSQL) 쿼리
         ↓
결과 → Redis 캐싱
         ↓
응답 반환
```

---

## 🔑 주요 설정 파일 역할

| 파일 | 역할 |
|---|---|
| `turbo.json` | 각 앱/패키지의 빌드 의존성 정의, 병렬 실행 가능 범위 지정 |
| `pnpm-workspace.yaml` | pnpm에게 워크스페이스 폴더 알림 |
| `package.json` (각 앱) | 앱별 의존성, 빌드 스크립트 |
| `tsconfig.json` (각 앱) | TypeScript 컴파일 설정 |
| `next.config.js` (웹/관리자) | Next.js 최적화, 이미지 도메인 설정 |
| `drizzle.config.ts` | DB 마이그레이션 설정 |
| `.env.example` | 환경변수 가이드 |

---

## 📊 의존성 관계도

```
┌─────────────────────────────────────────┐
│          @helpbee/config                │ (TypeScript, ESLint 설정)
└──────────────────┬──────────────────────┘
                   │
        ┌──────────┼──────────┬──────────┐
        ↓          ↓          ↓          ↓
   @helpbee/   @helpbee/   @helpbee/  @helpbee/
   types       database     ui         api
        ↓          ↓          ↓          ↓
        └──────────┼──────────┴──────────┘
                   │
        ┌──────────┴──────────┬──────────┐
        ↓                     ↓          ↓
    @helpbee/web         @helpbee/admin  @helpbee/ai
   (Next.js 웹)        (Next.js 관리자)  (FastAPI)
```

---

## ⚡ 개발 시 자주 사용할 명령어

```bash
# 전체 개발 서버 시작
pnpm dev

# 특정 앱만 개발
pnpm --filter @helpbee/web dev
pnpm --filter @helpbee/api dev

# 모든 앱 빌드
pnpm build

# 타입 확인
pnpm type-check

# 린트 확인
pnpm lint

# DB 마이그레이션 생성
pnpm --filter @helpbee/database push

# Docker 서비스 시작/종료
docker-compose up -d
docker-compose down
```

---

## 💾 환경변수 참고

- `DATABASE_URL` - PostgreSQL (docker-compose 기본: `postgresql://helpbee_user:helpbee_password@localhost:5432/helpbee`)
- `REDIS_URL` - Redis (기본: `redis://localhost:6379`)
- `OPENAI_API_KEY` - OpenAI Vision API 키 (필수)
- `JWT_SECRET` - JWT 서명 키 (보안 필수)
- `API_PORT` - API 서버 포트 (기본: 3001)
- `AI_PORT` - AI 서버 포트 (기본: 8000)

---

## 🎯 다음 구현 단계 (향후)

1. ✅ 기본 폴더 구조 & 빈 파일 생성
2. ⬜ 각 앱 기본 페이지 & 라우트 구현
3. ⬜ DB 스키마 정의 및 마이그레이션
4. ⬜ API 엔드포인트 구현
5. ⬜ AI 분석 로직 구현
6. ⬜ 인증/권한 시스템
7. ⬜ 테스트 작성
8. ⬜ 배포 설정 (Docker, CI/CD)

