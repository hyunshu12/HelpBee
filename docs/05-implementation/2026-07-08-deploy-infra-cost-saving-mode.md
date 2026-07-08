# 배포 인프라 절감 모드 — 계획 확정 + 컨테이너화/배포 파이프라인/보안 기반 (PR #46~#51)

- **날짜**: 2026-07-07 ~ 2026-07-08
- **PR**: #46(build 버그) → #47(컨테이너화) → #48(client-ip) → #49(배포 워크플로) → #50(관측/보안) → #51(레거시 정리+문서, 이 PR)
- **계획서(단일 소스)**: [`plans/2026-07-07_배포인프라-절감모드.md`](../../plans/2026-07-07_배포인프라-절감모드.md)
- **권위 문서**: [`infra/CLAUDE.md`](../../infra/CLAUDE.md) 상단 "🚨 절감 모드" 섹션

## 배경

베타(~100명)를 ECS Fargate 정식 구성($175~235/월) 대신 **단일 EC2 절감 모드(~$66~71/월 AWS)** 로
가기로 결정. Fable 5 오케스트레이션 + Sonnet 서브에이전트 7차원 병렬 감사 + 비용/정합성 교차
검증으로 기존 인프라 계획을 점검한 뒤 계획서를 재작성했다.

## 감사에서 발견해 수정한 결함

| 발견 | 수정 |
|---|---|
| `apps/api` build 스크립트가 컴파일 후 서버를 실행 (`tsc && node dist/index.js`) — Docker 빌드 차단 | #46 |
| `node dist/index.js` 런타임 자체가 동작 불가 (확장자 없는 ESM import + workspace 패키지가 TS 소스 export) — start 스크립트가 한 번도 동작한 적 없음 | #47 (런타임=tsx로 통일) |
| `client-ip.ts`가 CloudFront+ALB 2-hop 전제 → 절감 모드에서 XFF 위조로 quota 우회·타인 잠금·감사 IP 오염 가능 | #48 (TRUSTED_PROXY=cloudflare) |
| Sentry가 계획 문서엔 "연동됨"으로 기재, 실제 SDK 0건 | #50 |
| `docker-compose.yml` DB 비밀번호 평문 커밋 (히스토리 잔존) | #47(변수화) + #50(gitleaks 게이트) |
| `seeds/dev.ts` 고정 비밀번호 git 공개 — 실환경 실행 시 즉시 침해 벡터 | #50 (prod.ts 신설 + dev 가드) |
| Terraform state 버킷 이름 문서/코드 불일치 + 실존하지 않음 (`init` 실패 실측) | #51 (레거시 삭제 + 이름 통일 명문화) |

## 산출물

- `apps/api/Dockerfile`, `apps/ai/Dockerfile`, `.dockerignore`, `docker-compose.beta.yml`, `infra/docker/caddy/Caddyfile` (#47)
- `.github/workflows/docker-build.yml`(PR 빌드 게이트 — 로컬 Docker 없음), `deploy-beta.yml`(dispatch 전용+Environment 승인), `gitleaks.yml` (#47/#49/#50)
- `scripts/deploy-ec2.sh`(SSM 멱등 배포), `scripts/backup-db.sh`(pg_dump→S3+CloudWatch 메트릭), `scripts/restore-drill.sh` (#49/#50)
- `apps/api/src/lib/{client-ip,sentry}.ts`, `packages/database/src/seeds/prod.ts` (#48/#50)
- 레거시 삭제: `infra/terraform/environments/`, `modules/eks/`, `infra/k8s/`, 루트 `services/` — 참조 0건 확인 후 trash (#51)

## 알려진 제약 / 후속

- **Terraform(PR-2/3)은 미착수** — 사람 액션 P0(ROOT 키 회전, helpbee.kr 구매, 관리자 권한 재고 확인, OIDC/tf-state 부트스트랩) 대기. 계획서 §3·§4 참조.
- deploy-beta.yml 자동 트리거(workflow_run)는 Environment `beta`에 required reviewers 설정 후 활성화.
- ONNX CPU 추론 동시성 미검증 — 베타 오픈 전 k6 부하 게이트 (계획서 §4 마지막).
- Vercel Pro($20/월) 채택 여부 미결정 (admin이 상업용 Node 프록시 — Hobby ToS 소지).
