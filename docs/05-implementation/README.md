# docs/05-implementation — 구현 완료 기록 (Implementation Log)

이 디렉터리는 **PR 머지된 구현의 영구 기록**이다.
cold-pickup AI / 신규 합류한 사람이 "지금까지 무엇이 구현됐는지" 한눈에 보는 인덱스 역할을 한다.

git log를 뒤지지 말고 여기를 먼저 읽자.

---

## 파일명 규칙

```
YYYY-MM-DD-{topic-kebab-case}.md
```

- 날짜: PR 머지된 (또는 머지 예정) 날짜
- topic: 구현 주제. 짧고 검색 가능하게 (예: `database-schema`, `api-auth-hives`, `ui-tokens-core-components`)

## 작성 시점

1. **PR 머지 직후**: 같은 브랜치에서 추가 또는 후속 PR로 작성.
2. **큰 PR은 머지 전 동시 작성**: 구현과 함께 같은 PR에 포함하면 리뷰어가 변경 의도를 빠르게 파악.

## 템플릿

```markdown
# YYYY-MM-DD — {제목}

> PR: #N · 브랜치: feature/xxx → develop · 머지일: YYYY-MM-DD

## 범위 (Scope)

한 줄로 무엇을 했는지.

## 산출물 (Deliverables)

- 파일 경로 + 한 줄 설명
- ...

## 검증 (Verification)

- 어떤 명령으로 통과 확인했는지
- 알려진 제약 / 후속 검증 항목

## 후속 작업 (Follow-up)

- 이 구현으로 풀린 의존성 (다음 가능한 PR)
- 분리한 범위 밖 항목

## 참조

- 권위 가이드: `domain/CLAUDE.md`
- 관련 마이그레이션 / 문서 링크
```

## 작성 의무

각 PR 머지 시 **하나의 기록 파일**을 추가한다.
의무 항목:
- [ ] 산출물 파일 경로 누락 없이 나열
- [ ] 알려진 제약 / 후속 작업 명시 (있다면)
- [ ] 권위 CLAUDE.md 또는 관련 docs 링크
- [ ] 루트 `CLAUDE.md` "참고 문서 가이드" 섹션 갱신 (필요 시)

## 인덱스

| 날짜 | 주제 | PR | 파일 |
|---|---|---|---|
| 2026-05-11 | Database 9-table schema + types 동기화 + impl log 체계 도입 | (TBD) | [2026-05-11-database-schema.md](./2026-05-11-database-schema.md) |
| 2026-06-08 | YOLO v0.1.0 varroa 검출기 베이스라인 전체 사이클 (스윕→학습→golden→sign-off GO, copy_paste no-op 발견) | (이 PR) | [2026-06-08-v010-yolo-baseline.md](./2026-06-08-v010-yolo-baseline.md) |
| 2026-06-16 | Flutter 모바일 scaffold + 인증 플로우 (스플래시/온보딩/로그인/회원가입, 토큰 회전·single-flight refresh, Figma 토큰) | (예정) | [2026-06-16-mobile-scaffold-auth.md](./2026-06-16-mobile-scaffold-auth.md) |
| 2026-06-16 | YOLO 추론 수정: ONNX decode(nms=False raw 대응) + 전처리 q95(응애 false negative/train-serve skew 해소) | #24, #25 (OPEN/미머지) | [2026-06-16-yolo-inference-decode-and-preprocess-fixes.md](./2026-06-16-yolo-inference-decode-and-preprocess-fixes.md) |
| 2026-06-16 | 모바일 벌통(Hive) CRUD + 실데이터 홈 `/v1/hives` 연동 + 로컬 DB·백엔드 기동·라이브 검증 | #28 (머지) | [2026-06-16-mobile-hives-integration.md](./2026-06-16-mobile-hives-integration.md) |
| 2026-06-16 | 모바일 앱 셸(하단 네비)+설정/이력/프로필 + 홈·벌통상세 Figma 정합 + 분석 백엔드 온라인화(AI서버·S3·E2E) + 적대적 리뷰 수정 | (예정) | [2026-06-16-mobile-app-shell-and-analysis-online.md](./2026-06-16-mobile-app-shell-and-analysis-online.md) |
| 2026-06-17 | 모바일 진단 흐름 5화면(카메라→검토→분석중→레포트) + 이미지 업로드 파이프라인(presign/S3/confirm) + RiskGauge + 적대적 리뷰 수정 | #29 (머지) | [2026-06-17-mobile-analysis-flow.md](./2026-06-17-mobile-analysis-flow.md) |
| 2026-06-17 | 벌통 등록 풀스크린 폼(바텀시트→전용 화면, 설치일 날짜선택·GPS 버튼·히어로 배너) | #30 (머지) | [2026-06-17-mobile-hive-register-fullscreen.md](./2026-06-17-mobile-hive-register-fullscreen.md) |
| 2026-06-17 | 벌통 수정 화면(등록 폼 일반화·재사용) + ⋮수정 dead-end 제거 + controller updateHive | #31 (머지) | [2026-06-17-mobile-hive-edit.md](./2026-06-17-mobile-hive-edit.md) |
| 2026-06-17 | 웹 프론트엔드 MVP(apps/web) + 디자인 시스템(@helpbee/ui): Figma 4페이지 + 법적/SEO/블로그, next-intl ko+en골격, S-Core Dream self-host, 25 SSG green | #33 (머지) | [2026-06-17-web-frontend-mvp.md](./2026-06-17-web-frontend-mvp.md) |
| 2026-07-04 | **전체 시스템 라이브 점검**: 4앱 테스트 스위트 + 진단 E2E(presign→S3→confirm→YOLO 추론 성공, 197ms) 실측 · 문제 9건 발견 · 개선 계획(P0~P2)은 루트 CLAUDE.md §C | 없음 (점검) | [2026-07-04-system-check.md](./2026-07-04-system-check.md) |
| 2026-07-04 | **Admin 대시보드 MVP**(apps/admin 최초 구현): 쿠키+프록시 인증, KPI/사용자관리/감사로그/dual 뷰, @helpbee/ui Table 추가, 라이브 E2E 검증 | #42 (머지) | [2026-07-04-admin-dashboard-mvp.md](./2026-07-04-admin-dashboard-mvp.md) |
| 2026-07-04 | 문의 접수(Inquiries) E2E: DB 테이블+쿼리(0002 migration)·API 라우트(5/시간 IP·허니팟)·웹 폼 실제 연결. 라우트 404 해소, 라이브 검증(201/psql/429) | (재발행 예정) | [2026-07-04-inquiries.md](./2026-07-04-inquiries.md) |
| 2026-07-04 | 분석 권장조치(recommendations) end-to-end: AI tier문구(+정직성 caveat) → API 반환(POST·GET:id, 목록 제외) → 모바일 레포트 severity 렌더 | #36 (예정) | [2026-07-04-analysis-recommendations.md](./2026-07-04-analysis-recommendations.md) |
| 2026-07-04 | 실패 분석 재시도: `POST /analyses`가 같은 imageId의 failed 행을 제자리 재추론·UPDATE(id 보존, CAS) → 200, success는 멱등 유지 + 모바일 "다시 시도" 버튼 | #37 (예정, #36 스택) | [2026-07-04-analysis-retry.md](./2026-07-04-analysis-retry.md) |
| 2026-07-04 | 첫 GitHub Actions CI 파이프라인(`.github/workflows/ci.yml`): node(type-check+api vitest)·ai(pytest)·mobile(analyze+test). 모든 스텝 develop 로컬 선검증 | #38 (예정) | [2026-07-04-ci-pipeline.md](./2026-07-04-ci-pipeline.md) |
| 2026-07-04 | AI 회귀 fixture 게이트(P1-3): 서빙 경로 스냅샷 매니페스트(이미지 미커밋·라이선스) + `-m regression` 24케이스 + skip 규칙 | #39 (예정) | [2026-07-04-ai-regression-fixtures.md](./2026-07-04-ai-regression-fixtures.md) |
| 2026-07-04 | dev 서버 .env 자동 로드 (api --env-file-if-exists / ai load_dotenv, 기존 env 우선) | #40 | [2026-07-04-dev-env-autoload.md](./2026-07-04-dev-env-autoload.md) |
| 2026-07-05 | 이메일 인증 발송(P1-4): stateless HMAC 토큰 + provider 추상화(console/Resend) + verify-email HTML·resend-verification(3/hr) → 분석 게이트 라이브 통과, 실 Resend messageId 확인 | #44 (예정) | [2026-07-05-email-verification.md](./2026-07-05-email-verification.md) |
| 2026-07-08 | **배포 인프라 절감 모드**: 계획 확정(단일 EC2, ~$66/월) + api/ai 컨테이너화(tsx 런타임) + client-ip Cloudflare 대응 + SSM 배포 워크플로 + Sentry/gitleaks/백업/prod시드 + 레거시 IaC 삭제 | #46~#51 | [2026-07-08-deploy-infra-cost-saving-mode.md](./2026-07-08-deploy-infra-cost-saving-mode.md) |
| 2026-08-12 | 한국어 어절 중간 줄바꿈 수정: 웹 전역 `word-break: keep-all`(+overflow-wrap) · 홈 인용 `text-balance` · 모바일 `keepAll()`(WORD JOINER) 9개 화면 | #52 (예정) | [2026-08-12-korean-text-wrapping.md](./2026-08-12-korean-text-wrapping.md) |

(새 기록 추가 시 위 표 갱신)
