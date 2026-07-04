# 2026-07-04 — 문의 접수(Inquiries) 기능 end-to-end

> PR: #41 (예정, feature/inquiries → develop, feature/web-frontend-mvp=#33 스택) · 머지일: (예정)

## 범위 (Scope)

`apps/web` 문의 폼이 실제로 백엔드에 접수되도록 DB 테이블 + API 라우트 + 웹 폼 연결을 end-to-end로 구현.
이전에는 `POST /v1/inquiries`가 404(라우트 없음)였고 폼은 "준비 중" 안내만 표시했다.

## 산출물 (Deliverables)

### packages/database
- `src/schema/inquiries.ts` — inquiries 테이블(id uuid PK, name, email, message, locale nullable, status new|answered|closed CHECK, timestamps mixin). 익명(user FK 없음)·hard 보존. `Inquiry`/`NewInquiry`/`InquiryStatus`/`INQUIRY_STATUS_VALUES` export.
- `src/queries/inquiries.ts` — `createInquiry(db, input)` (화이트리스트 insert, Mass Assignment 차단).
- `src/schema/index.ts` · `src/queries/index.ts` · `src/index.ts` — 배럴/타입 재수출 추가.
- `migrations/0002_cooing_ezekiel_stane.sql` — `drizzle-kit generate:pg` 산출물 + CHECK 제약 수동 보강(0000 migration과 동일 컨벤션, drizzle-kit@0.20은 check() 미emit).

### apps/api
- `src/schemas/inquiries.ts` — zod `createInquirySchema`(name 1~60, email, message 10~2000, locale 'ko'|'en' optional, honeypot `website`). `.strict()`.
- `src/routes/inquiries.ts` — `POST /` 익명. 허니팟 채워지면 201 위장(DB 미저장). 응답 `{ id }`만(message echo 금지).
- `src/app.ts` — `inquiriesDeps` 와이어링 + `/v1/inquiries` 마운트 + **5/시간/IP 레이트리밋**(`rateLimit` windowSec 3600, prefix 'inquiries', keyFn getClientIp).
- `src/routes/inquiries.test.ts` — 8 테스트(201/locale null/400 검증×3/허니팟/레이트리밋 429).

### apps/web
- `src/lib/inquiries.ts` — `submitInquiry()` 를 실제 `fetch(POST ${NEXT_PUBLIC_API_URL}/v1/inquiries)`로 교체. `type`은 message 접두로 합쳐 전송(백엔드 스키마는 name/email/message/locale만). 결과 `{ok:true,id}` / `{ok:false, reason}`(RATE_LIMITED·VALIDATION_FAILED·NETWORK·MISCONFIGURED).
- `src/components/contact/ContactForm.tsx` — 성공 시 폼 reset + 성공 배너, 실패 시 code별 메시지, `useLocale()`로 locale 전달. 로딩은 기존 `isSubmitting`.
- `messages/ko.json` · `messages/en.json` — `contact.form`의 `notImplemented` → `success`/`error`/`rateLimited` 키로 교체.

### docs
- `docs/01-development/frontend-api-integration.md` — §5.5 Inquiries 추가, §7.1 레이트리밋 표 행 추가, §10 Readiness에 ✅ 행 추가, §11 참조 갱신.
- `apps/web/CLAUDE.md` — "/inquiries 미구현" 경고 → 구현 완료로 현행화.

## 검증 (Verification)

- `pnpm --filter @helpbee/database generate:pg` → `0002_*.sql` 생성, `drizzle-kit check:pg` **clean**(drift 없음). `migrate` 로컬 적용 → `\d inquiries`에 3 인덱스 + `inquiries_status_check` 확인.
- `pnpm --filter api test` **173 passed / 17 files**(기존 165 + 신규 8). `type-check` clean.
- `pnpm --filter @helpbee/web build` **PASS**(25 SSG 유지, /ko·/en/contact 포함). `type-check` clean. `@helpbee/database type-check` clean.
- **라이브 E2E**(로컬 API :3001 + 웹 :3000):
  - happy path → **201** `{id: 2122d7fd-…}`, psql `inquiries` row(status `new`) 확인.
  - message 짧음 → **400**, 잘못된 이메일 → 400.
  - 허니팟(website) → **201** 위장 + DB 미저장(총 1행, spam 0행 확인).
  - 5회 연속 201 → **6번째 429** + `retry-after: 3600`.
  - `GET /ko/contact` → **200**, 폼 렌더 확인.

## 후속 작업 (Follow-up)

- 이메일 알림/자동회신 미구현(현재 저장만).
- 어드민 문의 목록/상태 관리 UI(`status: new→answered→closed`) 미구현 — `apps/admin`에 후속.
- 검증 실패 응답이 zValidator 기본 포맷(`{success,error}`)이라 문의만 problem+json 아님 — 프론트는 status로 분기하므로 무해하나, 전역 zValidator 훅으로 통일 시 함께 정리.
- prod CORS_ALLOWLIST에 `https://helpbee.kr` 추가 필요(현재 로컬 localhost:3000만).

## 참조

- 권위 가이드: `packages/database/CLAUDE.md`, `apps/api/CLAUDE.md`, `apps/web/CLAUDE.md`
- 계약: `docs/01-development/frontend-api-integration.md` §5.5
- 마이그레이션: `packages/database/migrations/0002_cooing_ezekiel_stane.sql`
