# HelpBee 아키텍처 설계

## 시스템 아키텍처

```
사용자 브라우저
    ↓
  ALB + NGINX Ingress
    ↓
  ┌──────────────────────────────────────────┐
  │         Kubernetes (EKS)                 │
  │  auth-service  user-service  analysis    │
  │  (port 8001)   (port 8002)  (port 8003)  │
  └──────────────────────────────────────────┘
    ↓                   ↓              ↓
  PostgreSQL         PostgreSQL    OpenAI API
  (auth schema)      (user schema) (GPT-4o)
```

## 마이크로서비스 경계

| 서비스 | 책임 | DB 스키마 |
|--------|------|-----------|
| auth | 인증/인가, JWT | helpbee_auth |
| user | 프로필, 벌통, 구독 | helpbee_user |
| analysis | AI 분석, 리포트 | helpbee_analysis |

## API 게이트웨이 라우팅

```
/api/auth/*     → auth-service:8001
/api/users/*    → user-service:8002
/api/analysis/* → analysis-service:8003
```

## 데이터 흐름 (이미지 분석)

```
1. 클라이언트 → API GW → auth-service (JWT 검증)
2. 클라이언트 → API GW → user-service (S3 Presigned URL 발급)
3. 클라이언트 → S3 (직접 업로드)
4. 클라이언트 → API GW → analysis-service (분석 요청)
5. analysis-service → OpenAI Vision API (이미지 분석)
6. analysis-service → DB (결과 저장)
7. 클라이언트 → 결과 조회
```

## 기술 선택 근거

| 기술 | 선택 이유 |
|------|-----------|
| FastAPI | OpenAI SDK 생태계, async 지원, 타입 안전 |
| Next.js 14 | SSR, 이미지 최적화, App Router |
| PostgreSQL | 스키마 분리로 서비스 격리, ACID 보장 |
| EKS | 오토스케일링, 서비스 독립 배포 |
| Terraform | IaC, 환경 간 일관성 |
