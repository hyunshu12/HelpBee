# 이메일 인증 발송 운영 런북 (Email Verification Runbook)

> 최종 갱신: 2026-07-05 (PR #44 머지 기준) · 구현 기록: [docs/05-implementation/2026-07-05-email-verification.md](../05-implementation/2026-07-05-email-verification.md)
> 담당 코드: `apps/api/src/services/email-service.ts` · 라우트: `apps/api/src/routes/auth.ts`

---

## 1. 현재 상태 (2026-07-05)

| 항목 | 상태 |
|---|---|
| 발송 provider | **Resend** (`EMAIL_PROVIDER=resend`, 로컬 `.env` 설정 완료) |
| Resend 계정 소유자 | **mrmrsmartfarm@gmail.com** |
| 발신 주소 | `onboarding@resend.dev` (Resend 기본 — 도메인 인증 전) |
| 발송 가능 범위 | ⚠️ **계정 소유자 주소로만 배달됨** (도메인 미인증 제약) |
| 도메인 | **helpbee.kr 미구매** (2026-07-05 whois 기준 등록 가능 상태 확인. helpbee.com은 2014년부터 타인 소유 — 구매 불가) |
| 실발송 검증 | ✅ 완료 — messageId `d1a130a1-0cce-4ea5-ad33-9d3aa15ac8f4` (소유자 주소 배달 확인) |

**한 줄 요약: 코드는 완성. 실사용자에게 메일을 보내려면 §4의 도메인 절차만 남았다.**

---

## 2. 동작 방식

```
signup(201) ──(발송 실패해도 가입은 성공)──▶ 인증 메일
                                              │  [HelpBee] 이메일 인증을 완료해주세요
                                              ▼
                          GET /v1/auth/verify-email?token=...
                          (한국어 HTML: 성공/만료/무효 3-state)
                                              │
                                              ▼
                          users.email_verified_at = now()  → 분석 403 게이트 해제
```

- **토큰**: stateless HMAC-SHA256 (`email-verify:` purpose 분리, JWT_SECRET 파생). **DB 테이블 없음.** 만료 24h, 이메일 바인딩(이메일 변경 시 기존 링크 무효). 인증 성공은 idempotent + audit_log(`auth.email_verified`).
- **재발송**: `POST /v1/auth/resend-verification` 🔐 — **3회/시간/user**. 이미 인증 시 409 `AUTH_EMAIL_ALREADY_VERIFIED`.
- **발송 실패 정책**: 로그 warn 후 계속 — **가입(201)을 절대 실패시키지 않는다.** 사용자는 재발송 엔드포인트로 복구.

## 3. 환경변수 (`apps/api/.env` — dev 서버가 자동 로드, PR #40)

```bash
EMAIL_PROVIDER=resend            # console | resend (기본 console)
RESEND_API_KEY=re_...            # provider=resend일 때 필수 (env 검증이 fail-fast)
EMAIL_FROM="HelpBee <onboarding@resend.dev>"   # 도메인 인증 후 no-reply@helpbee.kr 로 교체
EMAIL_VERIFY_BASE_URL=http://localhost:3001    # 배포 후 https://api.helpbee.kr
```

- **`console` 모드**: 실발송 없이 인증 URL을 서버 로그(pino)로 출력 — 개발/CI 기본. 프로덕션에서 console이면 부팅 시 경고 로그.
- CI/테스트는 키 불필요 (vitest는 mocked fetch / ConsoleSender).
- 프로덕션 키는 `.env`가 아니라 **AWS Secrets Manager** (`helpbee/prod/resend`) — 인프라 구축 시.

## 4. 🎯 실사용자 발송 활성화 절차 (베타 전 필수, 미완)

1. **helpbee.kr 구매** — 가비아(gabia.com) 권장(인프라 계획 기준). 연 ₩13,000~22,000. ← **사람 액션**
2. **Resend 도메인 인증** — resend.com/domains → `helpbee.kr` 추가 → 표시되는 DNS 레코드 3개(SPF/DKIM/DMARC)를 가비아 DNS 관리에 등록 → Verified 될 때까지 수 분~수 시간 대기. (Route53 이전은 인프라 단계에서 해도 무방 — 이전 시 레코드도 함께 이관)
3. **발신자 교체** — `.env`(및 추후 Secrets Manager)의 `EMAIL_FROM="HelpBee <no-reply@helpbee.kr>"`
4. **재검증** — 소유자가 아닌 주소로 가입 → 메일 수신 → 링크 클릭 → `GET /v1/auth/me`의 `emailVerified:true` 확인.

> 네이버/다음 메일 도달률은 provider가 아니라 **도메인 인증(SPF/DKIM/DMARC) 품질**이 좌우한다. 2번을 생략한 채 발송량을 늘리지 말 것.

## 5. 트러블슈팅

| 증상 | 원인 / 조치 |
|---|---|
| Resend 403 `validation_error: can only send testing emails to your own address` | 도메인 미인증 상태에서 소유자 외 주소로 발송 시도 — §4 진행. (정상 동작이며 가입 자체는 201로 성공함) |
| 부팅 실패 `[config] invalid environment: RESEND_API_KEY` | `EMAIL_PROVIDER=resend`인데 키가 비어 있음 → 키 입력 또는 `EMAIL_PROVIDER=console`로 전환 |
| 메일이 안 옴 (개발 중) | `EMAIL_PROVIDER=console`이면 발송 안 함 — 서버 로그에서 verify URL을 직접 열 것 |
| 사용자가 링크 만료(24h 초과) | 앱에서 재발송 요청 (모바일 UI 버튼은 후속 — repo 메서드 `resendVerification()`은 구현됨) |
| 재발송 429 | 3회/시간/user 레이트리밋 — `Retry-After` 헤더 안내 |
| 키 회전 필요 시 | resend.com → API Keys에서 재발급 → `.env`/Secrets Manager 교체 → 서버 재시작. 코드 변경 불필요 |

## 6. 후속 과제

- [ ] §4 도메인 절차 (베타 전 필수)
- [ ] 모바일: 403 `AUTH_EMAIL_NOT_VERIFIED` 화면에 "인증 메일 다시 받기" 버튼 연결 (repo 메서드는 준비됨)
- [ ] 프로덕션 키를 Secrets Manager로 이관 (인프라 구축 시)
- [ ] (선택) SES 전환 검토 — 발송량 증가 또는 AWS 통합 일원화 시. `EmailSender` 인터페이스에 `SesSender` 구현만 추가하면 됨 (선택 배경: 2026-07-04 대화 — Resend 단기 / SES 장기)
