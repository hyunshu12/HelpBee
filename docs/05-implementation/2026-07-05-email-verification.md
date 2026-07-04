# 2026-07-05 — 이메일 인증 발송 (P1-4)

> PR: #44 (예정) · 브랜치: feature/email-verification → develop · 머지일: 2026-07-05

## 범위 (Scope)

무료 사용자(=현재 전원)가 `email_verified` 전까지 `POST /v1/analyses`에서 차단(403
`AUTH_EMAIL_NOT_VERIFIED`)되는데 **인증 메일이 한 번도 발송되지 않던** 루프를 닫았다.
signup → 인증 메일 발송 → 링크 클릭 → `email_verified_at` set → 분석 게이트 통과.
루트 CLAUDE.md 백로그의 마지막 미착수 항목(P1-4).

## 산출물 (Deliverables)

- `apps/api/src/services/email-service.ts` (신규) — stateless HMAC 토큰(서명/검증) +
  `EmailSender` 추상화(`ConsoleSender`/`ResendSender`) + `createEmailSender` 팩토리 +
  인증 메일 HTML + 결과 랜딩 페이지(성공/만료/무효, 한국어·꿀색·18px+).
  - 토큰: `base64url(json{sub,em,exp}).sig`, `sig=HMAC-SHA256(JWT_SECRET, "email-verify:"+body)`.
    purpose 접두로 다른 HMAC과 분리, `em`(가입 시점 email) 바인딩으로 이메일 변경 후 무효화.
    **DB 테이블/마이그레이션 없음**(stateless). 24h 만료.
  - `ResendSender`: 글로벌 `fetch` POST `https://api.resend.com/emails`(신규 npm 의존성 0),
    10s 타임아웃 + 5xx/네트워크 1회 재시도, 실패는 warn 로그 후 resolve(**절대 signup 미차단**),
    성공 시 message id만 로그(키 미로그).
- `apps/api/src/routes/auth.ts` — signup 성공 경로에 발송(try/catch, 201 미차단) +
  `GET /v1/auth/verify-email?token=`(🔓, HTML 3-state, `email_verified_at` set + audit
  `auth.email_verified`, 멱등) + `POST /v1/auth/resend-verification`(🔐, 이미 인증 시 409,
  audit `auth.verification_resent`).
- `apps/api/src/app.ts` — `createEmailSender` 와이어링(prod+console 경고), authDeps 3개 추가
  (`sendVerificationEmail`/`verifyEmailToken`/`markEmailVerified`), 라우트 마운트:
  verify-email IP 30/min, resend-verification protectedAuth + **3회/시간/user** 레이트리밋.
- `apps/api/src/config/env.ts` — `EMAIL_PROVIDER`(enum console|resend, 기본 console)·
  `RESEND_API_KEY`(빈 문자열=미설정 transform)·`EMAIL_FROM`·`EMAIL_VERIFY_BASE_URL` +
  superRefine(resend일 때 키 필수).
- `apps/api/src/lib/error-codes.ts` — `AUTH_EMAIL_ALREADY_VERIFIED`(409) 추가.
- `packages/database/src/queries/accounts.ts` — `markEmailVerified(db, userId)`(idempotent,
  `WHERE email_verified_at IS NULL`, soft-deleted 제외).
- `apps/mobile/lib/features/auth/{data/auth_api.dart, data/auth_repository_impl.dart,
  domain/auth_repository.dart}` — `resendVerification()` 리포지토리 메서드(light touch).
  분석 error-state UI 버튼 연결은 **follow-up**으로 문서화(UI 강제 안 함, dart analyze 0 issues).
- 테스트: `apps/api/src/services/email-service.test.ts`(신규) + `routes/auth.test.ts` 확장.
- 문서: `.env.example`·`apps/api/CLAUDE.md`·`frontend-api-integration.md`(§1 표·§10 Readiness).

## 검증 (Verification)

- **vitest**: apps/api **203 passed** (기존 177 → +26). type-check PASS. mobile `dart analyze` 0 issues.
- **라이브 E2E (console)**: fresh signup(`emailVerified:false`) → 서버 로그의 verify URL curl →
  성공 HTML(200) → login → `GET /me` `emailVerified:true`. 이어서 hive→presign→S3 PUT(200)→
  confirm→`POST /analyses` = **200 `status:failed`(ai_unavailable)** — **403 게이트 통과 증명**.
- **resend**: 미인증 → 200 `{sent:true}`, 이미 인증 → 409 `AUTH_EMAIL_ALREADY_VERIFIED`,
  4번째/시간 → 429(3/hour/user 확인).
- **실 Resend 발송(resend provider)**: 계정 소유자(`mrmrsmartfarm@gmail.com`)로 발송 성공 —
  messageId `d1a130a1-…`. 미검증 도메인이라 그 외 주소(예: astre6099@gmail.com)는 Resend 403
  validation_error로 거부되나, **send 실패가 signup 201을 막지 않음**을 실증(warn 로그 후 계속).

## 결정 / 주의 (Decisions & Caveats)

- **stateless HMAC 토큰**(DB 무테이블) — refresh_tokens 같은 DB 조회 불필요, `em` 바인딩으로
  이메일 변경 후 옛 링크 자동 무효화. 서명키(JWT_SECRET) 회전 시 미검증 토큰은 만료 후 재발급 흡수.
- **이미 인증 시 409**(ok-noop 아님) — 모바일이 "이미 인증됨"을 명확히 구분하도록.
- **Resend 미검증 도메인 제약**: 실제 사용자 전송하려면 `resend.com/domains`에서 도메인 검증 후
  `EMAIL_FROM`을 그 도메인 주소로 교체 필요(운영 전 인프라 과제). 현재는 계정 소유자에게만 발송 가능.
- **follow-up**: 모바일 분석 error-state에 "인증 메일 다시 받기" 버튼 연결(리포지토리 메서드는 준비됨).
