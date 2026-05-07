# services/ — HelpBee 마이크로서비스

## Level: Enterprise

## 아키텍처

Clean Architecture (4-Layer) 패턴을 따릅니다.

```
API Layer       → FastAPI routers, DTOs, middleware
Application     → Service classes, Use Cases, Transactions
Domain          → Entities (pure Python), Repository interfaces (ABC)
Infrastructure  → SQLAlchemy, Redis, external API clients
```

## 서비스 목록

| 서비스 | 포트 | 역할 |
|--------|------|------|
| `auth` | 8001 | JWT 인증/인가, 세션 관리 |
| `user` | 8002 | 사용자 프로필, 구독 관리 |
| `analysis` | 8003 | AI 이미지 분석 (바로아 응애 진단) |

`shared/` — 공통 유틸리티 (에러 핸들러, 로깅, DB 연결)

## 규칙

- 서비스 간 직접 DB 공유 금지 (스키마 분리)
- 서비스 간 통신: 내부 HTTP API 또는 메시지 큐
- 각 서비스는 독립적으로 배포 가능해야 함
- 모든 엔드포인트에 Pydantic 타입 명시

## 의존성

```
services/{service}/
├── app/
│   ├── main.py
│   ├── routers/        # API Layer
│   ├── services/       # Application Layer
│   ├── domain/         # Domain Layer
│   ├── infrastructure/ # Infrastructure Layer
│   └── models/         # Pydantic DTOs
├── requirements.txt
└── Dockerfile
```
