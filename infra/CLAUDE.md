# HelpBee — DevOps, Storage & Deployment

이 문서는 HelpBee 인프라 도메인의 마스터 가이드다. AI 작업자(Claude)와 사람 운영자가 동일한 기준으로 작업하기 위한 단일 출처(single source of truth)다.

참고 플랜: `~/.claude/plans/refactored-percolating-church.md`

---

## 1. 목적 (Goal)

- **베타 100명 → 정식 런칭 500명** 트래픽을 안정적으로 감당하는 인프라 구성.
- **1인 운영 가능**해야 한다. 복잡도 < 운영 가능성.
- **월 운영비 ₩25만 이내** (≈ $175–$200) 를 목표로 한다. 베타 기간에는 더 낮게.
- 단계적 확장: vertical scale → horizontal scale. 베타 기간에 over-engineering 금지.
- 모든 인프라 변경은 코드(Terraform / GHA YAML / Dockerfile)로 표현한다. 콘솔 클릭으로 만든 자원은 "임시"로 간주하고 즉시 코드화한다.

운영 원칙
- 자동화 가능한 것은 자동화한다. 수작업은 README나 `scripts/`에 기록한다.
- prod 변경은 staging 검증 + 사람 승인 후에만 한다.
- 비용은 매주 모니터링한다. AWS Budgets 80% 알림은 Slack으로 받는다.

---

## 2. 클라우드 선택 (Cloud Provider)

| 영역 | 1순위 | 비고 |
| --- | --- | --- |
| 컴퓨트/네트워크 | **AWS Seoul (ap-northeast-2)** | Fargate + RDS + ElastiCache |
| GPU 학습 (YOLO) | **EC2 g5.xlarge Spot** | 학습 후 자동 terminate (`scripts/yolo-train-spot.sh`) |
| CDN/이미지 | **CloudFront + S3** | 한국 사용자 latency 충분 |
| 결제 도입 시 (Phase 2) | NCP 재검토 | KCP/이니시스 한국 결제 PG 연동 편의 |

선택 이유
- AWS는 한국 리전(ap-northeast-2)이 안정적이고 Fargate/RDS/ElastiCache 운영 부담이 가장 낮다.
- NCP는 한국 결제/통신사 특화이지만, 베타 단계에 PG 연동이 없으므로 Phase 2(결제 도입)에 재평가한다.
- GPU 학습은 1회성 / 배치성이므로 Spot으로 80% 비용 절감. 추론은 CPU 또는 small GPU 인스턴스에서 모델 로드.

---

## 3. 환경 분리 (Environments)

| 환경 | 위치 | 용도 | 비용/월 |
| --- | --- | --- | --- |
| **local** | dev 노트북 | docker-compose, 빠른 피드백 | $0 |
| **staging** | AWS, 단일 EC2 t4g.medium 또는 Fargate 0.5 vCPU x 1 task | PR 머지 검증, QA, 데모 | ≈ $30–$50 |
| **production** | AWS, Fargate 1 vCPU x 2 task (api/ai 분리) | 실제 사용자 | ≈ $175–$235 |

### 3.1 local
`docker-compose up -d` 로 다음을 띄운다.
- Postgres 16 (port 5432)
- Redis 7 (port 6379)
- (옵션) api (Hono), ai (FastAPI), admin (Next.js), web (Next.js)

`.env`는 `.env.example` 복사 후 로컬 값으로 채운다. **절대 git에 commit 금지**. (gitleaks pre-commit hook 권장)

### 3.2 staging
- 베타 직전(May W3) 까지 단일 EC2 t4g.medium 으로 시작.
- 트래픽이 늘면 Fargate 0.5 vCPU x 1 task 로 이전.
- DB: RDS db.t4g.micro 단일 AZ (백업 7일).
- 도메인: `staging.helpbee.kr` (Route53).

### 3.3 production
- ECS Fargate, api 1 vCPU x 2 task, ai 1 vCPU x 2 task. ALB로 분기.
- RDS PostgreSQL 16 db.t4g.small. 자동 백업 7일. **Multi-AZ는 Phase 2** (결제/매출 발생 후).
- ElastiCache Redis 7 cache.t4g.micro.
- CloudFront + S3 (이미지/정적 자산), Route53, ACM (TLS).
- Vertical scale 우선. CPU/메모리 한계 닿으면 task count 증가 (horizontal).

---

## 4. 폴더 구조 (Folder Layout)

```
helpbee/
├── apps/
│   ├── api/           # Hono (Node 20)
│   │   └── Dockerfile
│   ├── ai/            # FastAPI (Python 3.12)
│   │   ├── Dockerfile
│   │   └── Dockerfile.cuda   # 옵션, GPU 추론용
│   ├── admin/         # Next.js
│   │   └── Dockerfile
│   └── web/           # Next.js (마케팅/온보딩)
│       └── Dockerfile
├── infra/
│   ├── CLAUDE.md      # 이 문서
│   ├── terraform/
│   │   ├── modules/   # 재사용 모듈
│   │   │   ├── vpc/
│   │   │   ├── ecs/
│   │   │   ├── rds/
│   │   │   ├── elasticache/
│   │   │   ├── s3/
│   │   │   ├── cloudfront/
│   │   │   ├── route53/
│   │   │   ├── secrets/
│   │   │   ├── waf/
│   │   │   └── iam/
│   │   └── envs/
│   │       ├── staging/      # main.tf, terraform.tfvars, backend.tf
│   │       └── production/   # main.tf, terraform.tfvars, backend.tf
│   ├── docker/
│   │   └── nginx/     # 로컬 reverse proxy (옵션)
│   └── k6/            # 부하 테스트 스크립트
├── scripts/           # 운영용 bash/Python 스크립트
├── .github/
│   └── workflows/
│       ├── ci.yml
│       ├── deploy-staging.yml
│       ├── deploy-production.yml
│       └── mobile-beta.yml
├── docker-compose.yml
└── .env.example
```

> 각 앱의 `Dockerfile`은 해당 앱 폴더(`apps/<app>/Dockerfile`)에 둔다. infra/CLAUDE.md는 위치만 안내하며 실제 파일은 각 앱 도메인에서 작성한다.

---

## 5. 컨테이너화 (Containerization)

### 5.1 apps/api/Dockerfile (Hono, Node 20)
- Base: `node:20-alpine`.
- **Multi-stage build**: `deps` (pnpm install --frozen-lockfile) → `build` (turbo run build --filter=api) → `runner` (production deps only, non-root user, `tini` init).
- Turborepo 의 `--filter=api...` 와 pruned lockfile (`turbo prune --scope=api`)로 빌드 컨텍스트를 최소화한다.
- 실행: `node apps/api/dist/main.js`. PORT는 환경변수로 주입(8080).
- HEALTHCHECK: `wget -qO- http://localhost:8080/health || exit 1`.

### 5.2 apps/ai/Dockerfile (FastAPI, Python 3.12)
- Base: `python:3.12-slim`.
- Multi-stage: `builder` (uv 또는 pip wheel 빌드) → `runner` (slim, non-root).
- 의존성: `uvicorn`, `fastapi`, `pydantic`, `ultralytics`(YOLO 추론), `pillow`, `boto3`(S3).
- 실행: `uvicorn apps.ai.main:app --host 0.0.0.0 --port 8000 --workers 2`.

### 5.3 apps/ai/Dockerfile.cuda (옵션, GPU)
- Base: `nvidia/cuda:12.4.1-runtime-ubuntu22.04`.
- 베타 단계에는 사용 안 함. GPU 추론 필요 시 활성화.
- 학습은 `scripts/yolo-train-spot.sh`로 EC2 g5.xlarge Spot 띄워 실행.

### 5.4 apps/admin/Dockerfile, apps/web/Dockerfile (Next.js)
- Base: `node:20-alpine`.
- Next.js **standalone output** (`next.config.mjs` 의 `output: "standalone"`).
- Multi-stage: `deps` → `build` → `runner` (`.next/standalone` + `.next/static` + `public` 만 복사).
- 실행: `node server.js`. PORT 3000.

이미지 태그 정책
- Git short SHA + branch: `helpbee-api:main-a1b2c3d`.
- production은 git tag 도 함께: `helpbee-api:v0.3.0`.

---

## 6. Terraform 구조 (Terraform Layout)

### 6.1 modules/ (재사용 모듈)
| 모듈 | 책임 |
| --- | --- |
| `vpc/` | VPC, public/private subnet, NAT GW, route table |
| `ecs/` | ECS cluster, task definition, service, ALB target group |
| `rds/` | RDS PostgreSQL, parameter group, subnet group, backup |
| `elasticache/` | Redis cluster, subnet/parameter group |
| `s3/` | 버킷 + 라이프사이클 + 버전관리 + 암호화 |
| `cloudfront/` | distribution, OAC, behaviors |
| `route53/` | hosted zone, A/AAAA/CNAME records |
| `secrets/` | Secrets Manager secret + version |
| `waf/` | WebACL, AWS managed rule groups |
| `iam/` | task role, execution role, GHA OIDC role |

각 모듈은 `variables.tf`, `main.tf`, `outputs.tf`, `versions.tf`. README는 모듈 폴더에 둔다.

### 6.2 envs/staging, envs/production
- `main.tf` — 모듈 호출 (`module "vpc" {}`, `module "ecs" {}` …)
- `terraform.tfvars` — 환경별 값 (인스턴스 사이즈, task count, 도메인)
- `backend.tf` — S3 backend, key 분리:
  - staging: `key = "helpbee/staging/terraform.tfstate"`
  - production: `key = "helpbee/production/terraform.tfstate"`
  - bucket: `helpbee-tf-state` (versioning + 암호화 + DynamoDB lock 테이블)

작업 흐름
1. `terraform -chdir=infra/terraform/envs/<env> init`
2. `terraform -chdir=infra/terraform/envs/<env> plan -out=tfplan`
3. PR로 `plan` 결과를 첨부 (review).
4. 머지 후 `terraform apply tfplan` (staging은 GHA, production은 manual).

> **AI는 절대 직접 `apply` 하지 않는다.** plan diff를 PR 본문에 붙여 사람 리뷰를 받은 뒤에만 apply 한다.

---

## 7. CI/CD (.github/workflows)

| 워크플로 | 트리거 | 동작 |
| --- | --- | --- |
| `ci.yml` | PR | `pnpm install` → `turbo run lint type-check test` |
| `deploy-staging.yml` | `main` 머지 | docker build → ECR push → `aws ecs update-service` (force new deployment) |
| `deploy-production.yml` | tag `v0.x.0` push | **manual approval gate** (environment: production) → ECR push → ECS rolling update |
| `mobile-beta.yml` | mobile 디렉터리 변경 + tag | Flutter build → fastlane → TestFlight + Play Internal |

공통
- AWS 인증은 **OIDC** (GHA `aws-actions/configure-aws-credentials`). access key 저장 금지.
- ECR repo: `helpbee-api`, `helpbee-ai`, `helpbee-admin`, `helpbee-web`.
- `act -j ci` 로 로컬 시뮬 가능.

production 배포 가드
- environment `production` 에 reviewer 1명 이상 필수.
- 배포 전 staging smoke test 통과 확인.
- 실패 시 ECS task definition 이전 revision 으로 자동 롤백 시나리오 준비.

---

## 8. 시크릿 관리 (Secrets)

| 종류 | 저장소 | 예 |
| --- | --- | --- |
| 민감 (DB 패스워드, OpenAI 키, JWT secret) | **AWS Secrets Manager** | `helpbee/prod/db`, `helpbee/prod/openai` |
| 비민감 설정 (feature flag, region, log level) | **SSM Parameter Store** | `/helpbee/prod/log_level` |
| 로컬 개발 | `.env` (git ignored) | `.env.example` 만 commit |

원칙
- `.env`는 절대 commit 금지. **gitleaks** pre-commit hook 권장.
- ECS task 는 task role 로 Secrets Manager / SSM 에 접근. 환경변수에 평문 패스워드를 박지 않는다.
- 로컬에서 prod 시크릿이 필요한 경우는 거의 없다. 디버깅이라도 read-only 복제본을 쓴다.
- 대안: **Doppler** 또는 **Infisical** (팀 확장 시 검토).

---

## 9. 스토리지 (S3)

| 버킷 | 용도 | 정책 |
| --- | --- | --- |
| `helpbee-images-prod` | 사용자 사진 (벌통/벌 사진) | lifecycle: 30일 후 IA, 1년 후 Glacier. 암호화 SSE-S3. |
| `helpbee-images-staging` | 스테이징 사진 | lifecycle: 7일 후 삭제 |
| `helpbee-models` | YOLO weights, 학습 산출물 | **Versioning enabled**, 암호화 |
| `helpbee-tf-state` | Terraform state | Versioning + 암호화 + Public block |

CloudFront
- `cdn.helpbee.kr` 가 `helpbee-images-prod` 를 OAC(Origin Access Control)로 서빙.
- 캐시 정책: 이미지 7일, 메타 5분.
- 사진 업로드는 **presigned PUT URL** 방식 (api 서버가 발급).

---

## 10. DB / 캐시 (DB & Cache)

### RDS PostgreSQL 16
- prod: `db.t4g.small`, gp3 50GB, 자동 확장 200GB 한도.
- 자동 백업 7일. point-in-time recovery 활성.
- **Multi-AZ는 Phase 2** (월 +$30, 베타 단계 보류).
- Parameter group 별도 (timezone=Asia/Seoul, log_min_duration_statement=500ms).

### ElastiCache Redis 7
- `cache.t4g.micro` 1 노드.
- 용도: 세션, rate limit, 임시 추론 결과 캐시.
- 영속성 필요 데이터는 Redis에 두지 않는다 (RDS만 진실의 출처).

마이그레이션은 `apps/api` 의 ORM 마이그레이션(예: drizzle-kit / prisma migrate)을 GHA에서 deploy 직전에 실행한다.

---

## 11. 모니터링 / 옵저버빌리티 (Observability)

| 레이어 | 도구 |
| --- | --- |
| 인프라 metric/log | **CloudWatch** (ECS, RDS, ALB, ElastiCache) |
| 애플리케이션 에러 | **Sentry** — api(Hono), ai(FastAPI), admin/web(Next.js), Flutter |
| 대시보드 | **Grafana Cloud Free Tier** (10k metrics, 50GB logs) |
| APM (옵션) | OpenTelemetry → Grafana Tempo |

로그 포맷
- Hono(api): **pino** + JSON. request_id, user_id 포함.
- FastAPI(ai): **structlog** + JSON.
- Next.js: pino 또는 console + Sentry breadcrumb.
- 모든 로그는 stdout/stderr → CloudWatch Logs 로 수집 (ECS log driver: `awslogs`).

핵심 SLI
- API p95 latency < 500ms
- API 5xx < 1%
- AI 추론 p95 < 2s (이미지 1장 기준)
- 가용성 목표 99.5% (베타), 99.9% (런칭 후)

---

## 12. 알림 (Alerting)

CloudWatch Alarm → SNS topic → Lambda → **Slack webhook**.

기본 알람
| 알람 | 조건 |
| --- | --- |
| API 5xx 비율 | > 1% over 5min |
| AI 서비스 down | health check 실패 2회 연속 |
| RDS CPU | > 80% over 10min |
| RDS 디스크 | < 20% free |
| ALB target unhealthy | 1개 이상 5분 |
| AWS Budget | 월 예산의 80% 도달 |

긴급도
- **P1 (즉시)**: API down, AI down, DB down → Slack `#helpbee-alerts` + 모바일 푸시.
- **P2 (영업시간)**: latency 저하, 비용 초과 임박 → Slack only.

---

## 13. 도메인 / SSL (Domain & TLS)

- **helpbee.kr** (가비아 등록) + **helpbee.com** 방어 차원에서 확보.
- Route53 hosted zone (helpbee.kr).
- ACM 인증서: `*.helpbee.kr` (us-east-1, CloudFront용) + ap-northeast-2 (ALB용).
- 서브도메인 계획:
  - `helpbee.kr`, `www.helpbee.kr` — 마케팅(web)
  - `app.helpbee.kr` — 사용자 PWA (옵션)
  - `api.helpbee.kr` — Hono API
  - `ai.helpbee.kr` — FastAPI 추론 (또는 api 뒤로 숨김)
  - `admin.helpbee.kr` — 운영자 콘솔
  - `cdn.helpbee.kr` — CloudFront 이미지

---

## 14. WAF / 보안 (Security)

CloudFront 앞단에 **AWS WAF**:
- `AWSManagedRulesCommonRuleSet`
- `AWSManagedRulesKnownBadInputsRuleSet`
- (옵션) `AWSManagedRulesAmazonIpReputationList`
- **Rate limit**: 100 req/min/IP (기본).

기본 보안
- HTTPS-only (HTTP → HTTPS redirect at CloudFront/ALB).
- CORS allowlist: `https://helpbee.kr`, `https://app.helpbee.kr`, `https://admin.helpbee.kr`.
- JWT 만료 짧게 (access 15min, refresh 14d), refresh rotation.
- Admin은 IP allowlist 또는 Cognito + MFA.
- 정기 점검: dependabot, npm audit, pip-audit (GHA 주간 스케줄).

---

## 15. 백업 / DR (Backup & Disaster Recovery)

- **RDS 자동 백업 7일** + 매주 manual snapshot (수동 보관 30일).
- **S3 versioning** on (`helpbee-images-prod`, `helpbee-models`, `helpbee-tf-state`).
- 옵션: cross-region replication (`ap-northeast-2 → ap-northeast-1`) for `helpbee-images-prod`.
- **주간 복원 검증**: cron으로 staging RDS에 prod snapshot 복원 → 스모크 테스트 (`scripts/restore-drill.sh`, 추후 작성).
- RTO 4시간 / RPO 1시간 목표.

---

## 16. 부하 테스트 (Load Testing)

위치: `infra/k6/`

기본 시나리오
- VU 100 명, 5분간, 100 req/s.
- 검증: p95 < 500ms, error rate < 1%.
- 시나리오: 로그인 → 진단 이미지 업로드 → 결과 조회.

명령
```
k6 run infra/k6/scenarios/diagnose.js
```

릴리즈 전 체크: 매 마이너 버전마다 staging에서 1회 실행, 결과를 PR에 첨부.

---

## 17. 비용 추정 (Monthly Cost Estimate, USD)

| 항목 | 사양 | 월 비용 |
| --- | --- | --- |
| ECS Fargate | api 1 vCPU x 2 + ai 1 vCPU x 2 | $60–$80 |
| RDS PostgreSQL | db.t4g.small, gp3 50GB | $30–$40 |
| ElastiCache Redis | cache.t4g.micro | $12 |
| ALB | 1대 | $20 |
| NAT Gateway | 1 AZ | $35 |
| CloudFront + S3 | 100GB egress + 50GB 저장 | $15–$25 |
| Route53 + ACM | hosted zone 1 + 인증서 | $1 |
| CloudWatch + Sentry(team) | 로그 50GB + Sentry $26 | $30 |
| **합계 (production)** | | **$175 – $235 (≈ ₩23–₩31만)** |
| Staging | 단일 EC2 또는 작은 Fargate | $30–$50 추가 |

베타 기간(W1-W4)에는 NAT GW를 VPC endpoint 로 일부 우회하거나 단일 EC2 + docker 로 운영해 $80~$120 수준 유지가 가능하다.

---

## 18. 로컬 개발 명령어 (Local Dev Commands)

```sh
# 1. 컨테이너 띄우기
docker compose up -d            # postgres + redis + (옵션) api/ai

# 2. 앱 실행 (turbo)
pnpm install
pnpm dev                        # turbo run dev (전체)
pnpm dev --filter=api           # 특정 앱

# 3. Terraform 검증
terraform -chdir=infra/terraform/envs/staging init
terraform -chdir=infra/terraform/envs/staging plan

# 4. GHA 로컬 시뮬
act -j ci

# 5. k6 부하 테스트
k6 run infra/k6/scenarios/diagnose.js
```

---

## 19. AI 작업 가이드라인 (Rules for AI Agents)

이 저장소에서 Claude/AI 에이전트가 작업할 때 지켜야 하는 규칙. **사용자의 명시적 승인 없이 위반 금지.**

1. **Terraform 변경**은 항상 `terraform plan` diff 를 PR 본문에 붙이고 사람 리뷰를 받는다. **직접 `apply` 금지.**
2. **`.env`, secrets, 인증서는 절대 git commit 금지.** pre-commit gitleaks 권장. 우발적으로 commit 시 즉시 키 회전 + history rewrite 사람에게 요청.
3. **`rm` 금지.** macOS 환경에서는 `trash <path>` 사용 (recoverable).
4. **destructive 명령은 자동 차단됨** (글로벌 hook): `git reset --hard`, `git push --force`, `git clean -f`, `DROP DATABASE/TABLE`, `TRUNCATE TABLE`. 차단 우회 시도 금지.
5. **prod 영향 액션은 사용자 명시 승인 필수**:
   - production 배포 (`v*.*.*` 태그)
   - `terraform destroy` / `apply` on production
   - DB schema drop / column drop / 데이터 마이그레이션
   - Secrets Manager 시크릿 변경
   - Route53 / 도메인 / WAF 룰 변경
6. **단발성 운영 명령**은 README 또는 `scripts/`에 기록한다. "한 번만" 한 작업도 다음에 또 한다.
7. **GPU spot 학습**은 `scripts/yolo-train-spot.sh` (작성 예정) 사용. 학습 종료 후 EC2 자동 terminate. 수동 학습 후 인스턴스 방치 금지(비용).
8. **새 인프라 자원**은 콘솔이 아니라 Terraform 모듈로 추가한다. 콘솔에서 만든 자원은 즉시 import 하거나 재생성한다.
9. **비용 영향 변경**(인스턴스 사이즈 업, 멀티AZ, 새 NAT GW, 새 CloudFront)은 PR에 예상 월 증가액을 적는다.
10. **로그/시크릿 노출 주의**: 로그에 토큰/비밀번호/JWT를 그대로 찍지 않는다. PII는 마스킹.

---

## 📋 개발 계획 (마스터 플랜 발췌 — 정합 요약)

### 핵심 의사결정 (1줄 요약)
- **클라우드**: AWS Seoul (ap-northeast-2). NCP는 Phase 2 결제 도입 시 재검토
- **오케스트레이션**: ECS Fargate (운영 단순). K8s/EKS는 Phase 2 (DAU 5,000+)에 검토
- **DB/캐시**: RDS PostgreSQL 16 db.t4g.small + ElastiCache Redis 7 cache.t4g.micro. Multi-AZ는 Phase 2
- **스토리지**: S3 + CloudFront. helpbee-images-prod (사용자 사진, lifecycle 30일 IA → 1년 Glacier), helpbee-models (YOLO weights, versioning)
- **GPU**: EC2 g5.xlarge Spot (~$0.4/h)으로 YOLO 학습. 추론은 MVP에서 CPU(ONNX). 트래픽 증가 시 SageMaker Serverless
- **시크릿**: AWS Secrets Manager (DB, OpenAI, JWT) + SSM Parameter Store (non-sensitive)
- **모니터링**: CloudWatch + Sentry (api/ai/admin/web/Flutter) + Grafana Cloud Free
- **알림**: CloudWatch Alarms → SNS → Lambda → Slack webhook (5xx>1%, AI down, RDS CPU>80%, 예산 80%)
- **WAF/보안**: CloudFront + AWS WAF (CommonRuleSet, KnownBadInputs), HTTPS-only, CORS allowlist, 100 req/min/IP
- **백업/DR**: RDS automated backup 7일, weekly snapshot 복원 검증, RTO 4h / RPO 1h

### CI/CD 파이프라인
- **PR**: turbo run lint type-check test (캐시 활용)
- **main 머지**: build → ECR push → aws ecs update-service (staging 자동 배포)
- **tag v0.x.0**: production 배포 + manual approval 필수
- **Flutter (apps/mobile)**: GHA + fastlane → TestFlight (베타) / Internal Testing (Play)

### 도메인
- helpbee.kr (가비아) + helpbee.com 확보 권장
- Route53 + ACM
- 서브: api / ai / admin / www / cdn

### 검증 / 부하
- Staging smoke: /health, /ready
- terraform plan diff PR 리뷰 필수 (직접 apply 금지)
- k6 부하: 100 req/s 5분, p95 < 500ms, 에러 < 0.5%
- Sentry 에러율 < 0.5% 24h

### 다른 분야와의 인터페이스 (정합 포인트)
- **← 모든 앱**: 환경변수는 .env.example + AWS Secrets Manager, Dockerfile은 각 앱 폴더에 배치
- **↔ Flutter** (@apps/mobile): mobile-beta.yml에서 fastlane 빌드/배포
- **↔ AI 서비스** (@apps/ai): GPU spot 학습 인프라 + S3 helpbee-models 버킷 versioning
- **↔ DB** (@packages/database): RDS 백업 + 복원 drill에 의존. drizzle-kit migrate는 deploy 전 단계로 통합

---

## 20. 배포 전 체크리스트 (Pre-deploy Checklist)

production 배포 전 (체크 다 안 되면 배포 금지):

- [ ] `terraform plan` diff 검토 완료, 의도하지 않은 변경 없음
- [ ] staging 에서 동일 이미지로 24h 안정 운영
- [ ] k6 부하 테스트 p95 < 500ms / error < 1%
- [ ] Sentry 에러율 baseline 대비 증가 없음 (최근 1h)
- [ ] AWS Budget 80% 알림 미발생, 예상 월 비용 ₩31만 이내
- [ ] DB 마이그레이션 rollback 스크립트 존재
- [ ] smoke test pass (로그인 → 진단 → 결과 조회)
- [ ] 배포 시간 한국 영업시간 (10:00–17:00) 내, 금요일 오후 배포 금지

---

## 21. 마일스톤 (Milestones)

| 시기 | 작업 |
| --- | --- |
| **May W1** | docker-compose 확장 (api/ai/admin/web 추가), `.env.example` 정비 |
| **May W2** | GHA `ci.yml` (lint/type-check/test). ECR repo 생성 |
| **May W3** | Terraform 골격 + staging (`vpc`, `ecs`, `rds`, `s3`, `route53`) apply |
| **May W4** | 모니터링(CloudWatch + Sentry) + `staging.helpbee.kr` 도메인 연결 |
| **Jun**    | production 환경 구축, CloudFront/WAF, deploy-production.yml manual approval |
| **Jul–Aug** | 베타 100명 부하 검증, k6 시나리오 정착, 알람 튜닝 |
| **Sep**    | 보안 하드닝(WAF 룰 강화, Secrets 회전, IP allowlist), DR 복원 검증 |
| **Oct 1**  | 정식 런칭. 500명 트래픽 대비 horizontal scale 2 → 4 task |
| **Phase 2 (런칭 후)** | RDS Multi-AZ, NCP/PG 검토, GPU 추론 도입 검토 |

---

## 부록 A. 자주 쓰는 운영 명령

```sh
# ECS 강제 재배포 (이미지 태그 그대로)
aws ecs update-service --cluster helpbee-prod --service api --force-new-deployment

# 로그 tail
aws logs tail /ecs/helpbee/api --follow --since 5m

# RDS 수동 스냅샷
aws rds create-db-snapshot --db-instance-identifier helpbee-prod \
  --db-snapshot-identifier helpbee-prod-$(date +%Y%m%d)

# Secrets Manager 값 조회 (운영자만)
aws secretsmanager get-secret-value --secret-id helpbee/prod/db --query SecretString --output text
```

## 부록 B. 참고 링크

- AWS Fargate pricing: https://aws.amazon.com/fargate/pricing/
- Terraform AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- k6: https://k6.io/docs/
- Sentry: https://docs.sentry.io/

---

마지막 업데이트: 2026-05-02. 이 문서는 인프라 변경과 함께 갱신한다. PR 의 `infra/**` 변경은 반드시 이 문서에 영향이 있는지 확인한다.
