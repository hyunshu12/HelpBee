# 2026-07-04 — Admin 대시보드 MVP (apps/admin 최초 구현)

> PR: #35(예정) · 브랜치: feature/admin-dashboard-mvp → develop (**#33 feature/web-frontend-mvp 위에 스택** — @helpbee/ui 의존) · 머지일: (예정)

## 범위 (Scope)

`.gitkeep`뿐이던 apps/admin을 실동작 관리자 대시보드로 최초 구현: 로그인 → KPI 대시보드 → 사용자 관리(차단/복구·role 변경) → 감사 로그 → dual 분석 비교 뷰.

## 핵심 아키텍처 결정

- **포트 3002** (루트 CLAUDE.md 기준 — apps/admin/CLAUDE.md의 구 3001 표기 수정함)
- **httpOnly 쿠키 + 서버 프록시**: 브라우저 JS는 토큰을 절대 못 봄. 로그인은 `POST /api/session`(role≠admin이면 쿠키 미설정+403), 모든 백엔드 호출은 same-origin `/api/backend/[...path]` 프록시 경유(경로 allowlist: `admin/*`, `auth/me`) → CORS 불필요, `AUTH_TOKEN_EXPIRED` 시 refresh 1회 자동 회전 후 재시도
- **`src/middleware.ts`**: jose HS256 검증 + `role==='admin'` 강제. ⚠️ **함정: src/ 구조에서는 middleware.ts가 반드시 `src/` 안에 있어야 함** — 루트에 두면 Next가 조용히 무시 (구현 중 실제로 발생, 라이브 테스트에서 발견·수정)
- 데이터 페칭: TanStack Query v5 단일(`lib/api.ts`), 테이블: TanStack Table v8 래퍼(`DataTable`), 폼: react-hook-form+zod
- @helpbee/ui에 **Table** 프리미티브 추가(+test). Dialog 부재 → 파괴적 액션은 2-step 인라인 확인 패턴

## 산출물 (Deliverables)

- `packages/ui/src/components/Table.tsx`(+test) + index export
- `apps/admin/` 전체: config 7종(package.json·next.config.js·tailwind.config.ts·tsconfig·postcss·.eslintrc·.env.example), `src/middleware.ts`, `src/lib/*`(config·api·errors·types·query-keys·format·session·use-debounced-value), 라우트 핸들러 2종(`api/session`, `api/backend/[...path]`), 페이지 6종(login·대시보드·users·users/[id]·audit-log·analyses/[imageId]/dual)+not-found/error, 컴포넌트(KpiCard·DataTable·Banner·SidebarNav·LogoutButton·Select·ConfirmAction)
- `apps/web/.eslintrc.json` — 웹 lint 게이트 구멍(P1-2) 동시 해소
- `apps/admin/CLAUDE.md` 현행화(포트·env·Decision Log)

## 검증 (Verification)

- `pnpm --filter @helpbee/admin type-check · lint · build` 모두 PASS (8 routes + Middleware 32.2kB 번들 확인)
- `pnpm --filter @helpbee/ui test` 13/13 PASS
- **라이브 E2E** (API :3001 + admin :3002, 2026-07-04):
  - 미인증 `/` → 307 `/login` / admin 로그인 → 쿠키 설정+대시보드 200 / **일반 사용자 로그인 → 403 FORBIDDEN_ROLE(쿠키 미설정)**
  - 프록시: metrics·users·audit-logs 실데이터 / allowlist 밖(`hives`) 차단
  - PATCH 차단→복구 왕복 성공(백엔드 세션 회수 동작) / dual 뷰: yolo-only 이미지 → `{primary, secondary:null}` graceful 렌더

## 후속 작업 (Follow-up)

- 백엔드 `GET /v1/admin/users/:id` 부재 → 상세 페이지는 목록(pageSize=100) 캐시에서 조회. **백엔드에 단건 조회 라우트 추가 권장**
- Dialog 컴포넌트(@helpbee/ui, Radix), BboxOverlay(canvas), Recharts 추세, Playwright e2e, `/system` 헬스 페이지 — 전부 미포함(계획적 스코프 아웃)
- RSC 첫 페인트 대신 클라 컴포넌트+Skeleton (MVP 단순화, CLAUDE.md Decision Log 기록)

## 참조

- 권위 가이드: `apps/admin/CLAUDE.md` · 계약: `docs/01-development/frontend-api-integration.md` §6
- 로컬 기동: `apps/admin/.env.example` (API_URL + JWT_SECRET=apps/api와 동일, 서버 전용)
