# HelpBee - AI 기반 스마트 양봉 진단 SaaS 플랫폼

모노레포 기반의 풀스택 양봉 진단 플랫폼입니다. 사용자 웹앱, 관리자 대시보드, API 서버, AI 분석 서버를 단일 저장소에서 관리합니다.

## 📦 프로젝트 구조

```
helpbee/
├── apps/
│   ├── web/          # 사용자 웹앱 (Next.js 14+)
│   ├── admin/        # 관리자 대시보드 (Next.js 14+)
│   ├── api/          # API 서버 (Hono.js)
│   └── ai/           # AI 분석 서버 (FastAPI)
├── packages/
│   ├── types/        # 공유 TypeScript 타입
│   ├── ui/           # 공유 UI 컴포넌트 (shadcn/ui)
│   ├── database/     # Drizzle ORM 스키마
│   └── config/       # 공유 빌드/린트 설정
├── infra/            # Docker, 배포 스크립트
└── .github/          # CI/CD 워크플로우
```

## 🛠 기술 스택

| 레이어 | 기술 |
|---|---|
| **모노레포** | Turborepo + pnpm workspaces |
| **웹앱** | Next.js 14+, React 18, Tailwind CSS |
| **API** | Hono.js, TypeScript |
| **AI** | FastAPI, Python, OpenAI Vision API |
| **DB** | PostgreSQL, Drizzle ORM |
| **캐시** | Redis |
| **UI** | shadcn/ui, Tailwind CSS |
| **배포** | Docker, docker-compose |

## 🚀 빠른 시작

### 사전 요구사항
- Node.js ≥ 18.0.0
- pnpm ≥ 8.0.0
- Docker & Docker Compose
- Python 3.10+

### 설치

```bash
# 1. 저장소 클론 및 의존성 설치
git clone <repository>
cd helpbee
pnpm install

# 2. 환경변수 설정
cp .env.example .env.local

# 3. Docker로 DB 및 Redis 시작
docker-compose up -d

# 4. 전체 개발 서버 실행
pnpm dev
```

### 개별 앱 실행

```bash
# 웹앱 (http://localhost:3000)
pnpm --filter @helpbee/web dev

# 관리자 (http://localhost:3001)
pnpm --filter @helpbee/admin dev

# API 서버 (http://localhost:3001)
pnpm --filter @helpbee/api dev

# AI 서버 (http://localhost:8000)
cd apps/ai && python -m uvicorn app.main:app --reload
```

## 📚 개발 가이드

### 모노레포 명령어

```bash
# 전체 빌드
pnpm build

# 린트 확인
pnpm lint

# 타입 체크
pnpm type-check

# 테스트
pnpm test

# 정리
pnpm clean
```

### 새로운 패키지 추가

```bash
# packages 폴더에 새로운 패키지 생성
mkdir packages/my-package
cd packages/my-package
pnpm init
```

그 후 `package.json`의 `name` 필드를 `@helpbee/my-package`로 설정합니다.

## 🗄 데이터베이스

### 마이그레이션

```bash
# 마이그레이션 생성 (스키마 변경 후)
pnpm --filter @helpbee/database push

# 마이그레이션 적용
pnpm --filter @helpbee/database migrate
```

## 🔐 환경 변수

`.env.example`에서 `.env.local`로 복사 후 필요한 값을 입력하세요:

- `DATABASE_URL`: PostgreSQL 연결 문자열
- `REDIS_URL`: Redis 연결 문자열
- `OPENAI_API_KEY`: OpenAI API 키
- `JWT_SECRET`: JWT 서명 비밀키
- `AWS_*`: S3 이미지 저장소 인증정보

## 📝 라이센스

프로젝트별 라이센스 정보는 각 패키지의 `package.json`을 참고하세요.

## 📧 문의

문제나 질문은 GitHub Issues를 통해 보고해주세요.
