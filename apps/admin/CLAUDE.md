# apps/admin — HelpBee Admin Dashboard

> 이 문서는 `apps/admin` 워크스페이스 전용 가이드다. 루트 `CLAUDE.md`와 함께 읽는다.

---

## 1. 목적 (Purpose)

HelpBee 운영팀(내부 임직원, CS, 데이터 분석가)을 위한 **백오피스 / 운영 대시보드**.

다음 책임을 가진다:

- **사용자(User) 관리** — 가입/로그인 현황, 구독 상태, 차단/복구
- **진단(Analysis) 모니터링** — 모바일 앱에서 업로드된 응애·낭충봉아부패병 진단 결과 열람, AI 결과 vs 사람 라벨 비교, 재학습용 데이터 큐레이션
- **AI 사용량 / 비용 모니터링** — 일별 추론 호출 수, 모델 별 latency, 토큰/이미지 처리 비용
- **시스템 헬스 (System Health)** — `apps/api` 헬스체크, 큐 적체, DB 사용량
- **감사 로그 (Audit Log)** — 관리자 액션 (사용자 차단, 진단 라벨 수정 등) 추적

**핵심 사용자**: 5~15명 규모의 내부 팀. 모바일 대응 불필요(데스크톱 전용 OK).

---

## 2. 기술 스택 (Tech Stack)

| 영역            | 선택                                                                              |
| --------------- | --------------------------------------------------------------------------------- |
| Framework       | **Next.js 14 (App Router)** + **TypeScript (strict)**                             |
| 스타일링        | **Tailwind CSS** + `@helpbee/ui` (shadcn/ui 패턴)                                 |
| 데이터 페칭     | **TanStack Query v5** (클라 mutation/refetch) + RSC 첫 페인트                     |
| 테이블          | **TanStack Table v8** (정렬/필터/페이지네이션/컬럼 visibility)                    |
| 차트            | **Recharts** (라인/바/파이) — KPI 카드 + 추세 그래프                              |
| 진단 이미지 뷰어 | **react-zoom-pan-pinch** + Canvas 오버레이 (BboxOverlay 컴포넌트)                 |
| 폼              | **react-hook-form** + **zod**                                                     |
| 상태(전역)      | **zustand** (필요 최소)                                                           |
| 인증            | **자체 JWT** (apps/api와 시크릿 공유) + httpOnly 쿠키 + middleware.ts             |
| E2E 테스트      | **Playwright**                                                                    |
| 번들/빌드       | Next.js 기본 (Turbopack dev)                                                      |

> **금지**: NextAuth, Supabase Auth, Clerk 등 외부 인증. apps/api 자체 JWT 단일 소스.

---

## 3. 폴더 구조 (Folder Structure)

```
apps/admin/
├── CLAUDE.md
├── next.config.js
├── package.json
├── tsconfig.json
├── src/
│   ├── app/
│   │   ├── (auth)/
│   │   │   └── login/             # /login (인증 그룹, 사이드바 X)
│   │   └── (dashboard)/           # 인증된 사용자만, 사이드바 + 헤더 레이아웃
│   │       ├── users/             # /users (목록/상세)
│   │       ├── analyses/          # /analyses (진단 목록/상세 + BboxOverlay)
│   │       ├── system/            # /system (헬스/큐/AI 비용)
│   │       └── audit-log/         # /audit-log
│   ├── lib/                       # api 클라, auth 헬퍼, query keys
│   └── components/
│       ├── charts/                # Recharts 래퍼 (LineCard, BarCard, KpiCard)
│       ├── tables/                # TanStack Table 래퍼 (DataTable, ColumnDef 모음)
│       └── viewer/                # BboxOverlay (Canvas + zoom-pan-pinch)
└── tests/                         # Playwright e2e
```

### 그룹 라우팅 의도

- `(auth)` — 로그인/패스워드 리셋. 헤더/사이드바 없는 미니멀 레이아웃.
- `(dashboard)` — 인증 + role='admin' 검증을 통과한 사용자만 접근. 공통 사이드바 레이아웃(`layout.tsx`)이 페이지를 감싼다.

---

## 4. 인증 (Authentication)

**모델**: 자체 JWT — `apps/api`와 동일한 시크릿(`JWT_SECRET`) 사용.

### 흐름

1. `/login` 페이지에서 이메일/비밀번호 입력 → `apps/api` `/auth/login` 호출
2. 응답으로 받은 JWT를 **httpOnly Secure SameSite=Lax 쿠키** (`hb_admin_token`) 로 저장
3. `middleware.ts`가 `(dashboard)` 모든 요청에서:
   - 쿠키 존재 + JWT signature 검증
   - payload `role === 'admin'` 확인
   - 실패 시 `/login`으로 리다이렉트
4. RSC/route handler에서는 `lib/auth.ts`의 `getCurrentAdmin()` 헬퍼로 토큰 디코드

### 보안 체크리스트

- [ ] JWT는 **절대 localStorage / sessionStorage에 저장 금지**
- [ ] `JWT_SECRET`은 server runtime env에만, `NEXT_PUBLIC_*` 접두사 금지
- [ ] CSRF — same-site lax 쿠키 + state-changing은 POST/PUT/DELETE만
- [ ] 로그아웃 시 쿠키 `Max-Age=0`로 즉시 만료

---

## 5. 데이터 페칭 (Data Fetching)

**원칙**: RSC 첫 페인트 + 클라 mutation은 TanStack Query.

| 시나리오                    | 방식                                                       |
| --------------------------- | ---------------------------------------------------------- |
| 페이지 첫 로딩 데이터       | RSC에서 `lib/api.ts` 직접 호출 (서버 측 fetch + 토큰 포함) |
| 클라 refetch / mutation     | `useQuery` / `useMutation` 훅                              |
| 실시간성 필요(시스템 헬스)  | `refetchInterval: 10_000` 폴링                             |
| 무한 스크롤 (감사 로그)     | `useInfiniteQuery`                                         |

### lib/api.ts 단일 클라이언트

- 모든 백엔드 호출은 `lib/api.ts`의 `apiFetch()` 단일 함수 경유
- 401 → 자동 `/login` 리다이렉트
- 5xx → toast로 에러 노출
- **컴포넌트에서 직접 `fetch()` 호출 금지**

### Query Key 규칙

```
['users', 'list', { page, search }]
['users', 'detail', userId]
['analyses', 'list', { filter }]
['analyses', 'detail', analysisId]
['system', 'health']
```

---

## 6. 주요 페이지 (Pages)

| Route                        | 역할                                                                  |
| ---------------------------- | --------------------------------------------------------------------- |
| `/login`                     | 이메일/비밀번호 로그인                                                |
| `/` (dashboard root)         | 핵심 KPI 카드 (DAU, 진단 수, AI 비용, 신규 가입) + 추세 그래프        |
| `/users`                     | 사용자 목록 (TanStack Table, 검색/필터/정렬)                          |
| `/users/[id]`                | 사용자 상세 (구독, 진단 이력, 차단/복구 액션)                         |
| `/analyses`                  | 진단 목록 (썸네일 그리드 + 필터: 모델 버전/병해명/신뢰도)             |
| `/analyses/[id]`             | 진단 상세: 원본 이미지 + **BboxOverlay** + AI 결과 + 사람 라벨 편집   |
| `/system`                    | apps/api 헬스, 큐 적체, DB 용량, AI 일별 비용 차트                    |
| `/audit-log`                 | 관리자 액션 로그 (무한 스크롤, 액션 종류 필터)                        |

---

## 7. UI 컴포넌트 (Components)

### packages/ui 우선 사용

`Button`, `Card`, `Dialog`, `Badge`, `Input`, `Tabs`, `Skeleton`, `Table` 등 기본 빌딩블록은 **`@helpbee/ui`에서 import**한다.

```ts
// OK
import { Button, Card } from '@helpbee/ui';

// NG — admin 안에서 새 Button 만들지 말 것
```

### admin 전용 컴포넌트만 `src/components`

- `charts/` — Recharts 래퍼 (`<KpiCard title value delta />`, `<LineCard data />`)
- `tables/` — TanStack Table 래퍼 (`<DataTable columns data />` + 컬럼 정의 모음)
- `viewer/BboxOverlay.tsx` — react-zoom-pan-pinch + Canvas로 진단 bbox 그리기

### BboxOverlay 핵심 동작

- 원본 이미지 위에 절대 좌표(bbox: x, y, w, h, label, confidence)를 Canvas로 렌더
- 줌/팬 시 좌표는 transform 매트릭스에 따라 자동 스케일
- 사람 라벨 편집 모드 — 드래그로 bbox 추가/수정 → `/analyses/[id]` PATCH

---

## 8. 로컬 개발 (Local Development)

```bash
# 루트에서
pnpm install
pnpm --filter admin dev          # http://localhost:3001
```

### 포트

- `apps/web` → 3000
- **`apps/admin` → 3001 (권장)**
- `apps/api` → 4000

`next.config.js` 또는 `package.json`의 `dev` 스크립트에서 `next dev -p 3001`로 고정한다.

### `.env.local` 필수

```bash
NEXT_PUBLIC_API_URL=http://localhost:4000
JWT_SECRET=<apps/api와 동일>
```

> `JWT_SECRET`이 apps/api와 다르면 모든 인증이 깨진다. 루트 `.env`에서 공유하는 패턴 권장.

---

## 9. 테스트 (Testing)

**Playwright e2e** 핵심 시나리오:

1. `/login` → 잘못된 비밀번호 → 에러 표시
2. `/login` → 올바른 어드민 계정 → `/`로 리다이렉트
3. `/users` → 검색 → 결과 필터링
4. `/users/[id]` → 차단 액션 → 토스트 + 상태 업데이트
5. `/analyses/[id]` → BboxOverlay 줌/팬 → 라벨 편집 저장

```bash
pnpm --filter admin test:e2e
```

유닛 테스트는 최소 — 비즈니스 로직 대부분이 apps/api에 있다.

---

## 10. 배포 (Deployment)

- **Vercel** + **Cloudflare Access (Zero Trust)** — 사내 도메인/구글 워크스페이스 그룹으로 1차 차단, JWT가 2차
- 프리뷰 배포는 PR마다 자동, 단 Cloudflare Access 정책으로 사내만 접근
- 환경: `JWT_SECRET`, `NEXT_PUBLIC_API_URL`은 Vercel env에 environment별 등록

---

## 11. AI 작업 가이드라인 (AI Coding Rules)

### MUST

1. **새 페이지는 반드시 `app/(dashboard)/` 또는 `app/(auth)/` 그룹 안**에 만든다
2. **모든 백엔드 호출은 `lib/api.ts` 단일 클라**를 통과시킨다
3. **TanStack Query만 사용**한다 — 컴포넌트에서 직접 `fetch()`/`axios()` 호출 금지
4. UI 빌딩블록은 **`@helpbee/ui`에서 먼저 찾는다**. 없으면 ui 패키지에 추가 후 사용
5. 폼은 **react-hook-form + zod resolver** — 다른 폼 라이브러리 도입 금지
6. 파일 삭제는 **`trash` 사용** (`rm` 금지 — 루트 hook이 막는다)
7. 새 환경변수 추가 시 `.env.example` 갱신 + 이 문서 §8 업데이트

### MUST NOT

- ❌ `localStorage`에 토큰/비밀번호/PII 저장
- ❌ NextAuth, Supabase Auth 같은 외부 인증 SDK 도입
- ❌ admin에 양봉가용 비즈니스 로직 추가 (그건 mobile/api 책임)
- ❌ Tailwind config 직접 확장 — 토큰은 `@helpbee/ui` preset에서만
- ❌ 거대한 client component — 데이터는 RSC, 인터랙션만 클라

### Decision Log

큰 결정(예: TanStack Query → SWR 전환)은 본 문서에 ADR 섹션을 만들고 기록한다.

---

## 📋 개발 계획 (마스터 플랜 발췌)

### 기능 범위
- 어드민 로그인 (role='admin' 검증)
- 대시보드 KPI: 전체/활성 사용자, 월간 진단 수, AI 비용 (OpenAI vs YOLO), 진단 성공률
- 사용자 관리: 목록 (검색/필터/정렬), 상세, 상태 변경
- 진단 관리: 목록 + 상세 (원본 이미지 + YOLO bbox overlay + OpenAI side-by-side 비교)
- AI 모델 사용 통계: 모델별 호출 수/응답 시간/비용 차트
- 시스템 헬스: /health 엔드포인트 폴링, AI 서비스 상태
- 감사 로그 뷰어

### 핵심 정책
- **인증**: 자체 JWT (apps/api 동일 시크릿), middleware.ts에서 토큰 + role 검증, httpOnly 쿠키 저장
- **데이터 페칭**: RSC로 첫 페인트(SSR) + TanStack Query로 클라이언트 상호작용 (mutation/refetch)
- **테이블**: TanStack Table v8, 서버사이드 페이지네이션/정렬/필터
- **차트**: Recharts (KPI 카드, 시계열)
- **이미지 뷰어**: react-zoom-pan-pinch + Canvas overlay로 YOLO bbox 렌더링
- **포트**: 3001 권장

### 마일스톤
- **5월 W3-W4**: 로그인 + 대시보드 KPI + 사용자 목록
- **6월 W1**: 진단 상세 + bbox overlay 비교 뷰 + 시스템 헬스
- **6월 W2-W3**: 감사 로그 + 보강
- **7-9월**: 콘텐츠 추가, GA4/Hotjar 도입, A/B 테스트

### 검증
- Playwright e2e: 로그인 → 사용자 목록 → 진단 상세 핵심 플로우 PASS
- Storybook(packages/ui) 시각 회귀 (Chromatic)

### 배포 / 보안
- Vercel (빌드 캐시/이미지 최적화/Preview 환경)
- Cloudflare Access (ZeroTrust) 사내 SSO 게이팅, IP 화이트리스트 백업
- env: NEXT_PUBLIC_API_URL, JWT_SECRET, NEXT_PUBLIC_GA_ID

### 리스크 / 미해결
- 디자인 리소스 부족 → shadcn 기본 + 꿀색 팔레트 커스터마이즈만으로 MVP
- 한국어 카피라이팅 외주 또는 양봉협회 자문 필요
- 장년층 UX → 폰트 18px+, 고대비, 음성 안내(Phase 2 검토)

### 다른 분야와의 인터페이스
- **← Backend API** (@apps/api): /admin/* 엔드포인트 호출. role='admin' 검증은 백엔드와 양쪽
- **← packages/ui**: 모든 컴포넌트는 packages/ui에서 import (직접 shadcn 사용 금지)
- **← packages/types**: API 응답 타입은 packages/types에서 import

---

## 12. 체크리스트 (PR Checklist)

새 기능 / 페이지 PR 시 다음을 확인:

- [ ] 새 라우트가 `(dashboard)` 또는 `(auth)` 그룹 안에 있다
- [ ] 데이터는 RSC 첫 페인트 + TanStack Query mutation 패턴을 따른다
- [ ] `fetch()`/`axios()` 직접 호출 없음 — 모두 `lib/api.ts` 경유
- [ ] UI는 `@helpbee/ui` 컴포넌트 사용 (없는 경우 ui 패키지 PR 분리)
- [ ] 폼은 react-hook-form + zod
- [ ] 인증 필요 페이지는 middleware.ts 매처에 포함됐다
- [ ] Playwright e2e 시나리오 추가 (사용자 인터랙션이 있는 경우)
- [ ] `.env.example`이 새 변수와 동기화됐다
- [ ] `pnpm --filter admin lint` / `typecheck` / `build` 모두 통과
- [ ] 컴포넌트에 PII가 직접 console.log되지 않는다
