/**
 * 이메일 인증 (P1-4). stateless HMAC 토큰 + provider 추상화. DB 테이블/마이그레이션 없음.
 *
 * 토큰 형식(ai-client.ts signInternalBearer 컨벤션 계승):
 *   `base64url(json{sub,em,exp}).sig`,  sig = base64url(HMAC-SHA256(JWT_SECRET, PURPOSE + body))
 *   - PURPOSE 접두("email-verify:")로 다른 HMAC(내부 AI 토큰 등)과 목적 분리 → 토큰 혼용 차단.
 *   - `em`(가입 시점 email) 바인딩 → 이후 이메일 변경 시 옛 링크 자동 무효화.
 *   - JWT_SECRET 재사용(별도 시크릿 추가 없음). 서명키 회전 시 미검증 토큰은 만료 후 재발급으로 흡수.
 *
 * EmailSender: ConsoleSender(로그만) / ResendSender(글로벌 fetch, 신규 의존성 없음).
 * ⚠️ 발송 실패는 절대 signup/resend 흐름을 깨뜨리지 않는다 — 실패는 warn 로그 + 계속.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';

const PURPOSE = 'email-verify:';
const DEFAULT_TTL_SEC = 24 * 60 * 60; // 24h
const SUBJECT = '[HelpBee] 이메일 인증을 완료해주세요';
const RESEND_ENDPOINT = 'https://api.resend.com/emails';

export type EmailVerifyPayload = { sub: string; em: string; exp: number };

function b64url(input: string): string {
  return Buffer.from(input).toString('base64url');
}
function sign(secret: string, body: string): string {
  return createHmac('sha256', secret).update(PURPOSE + body).digest('base64url');
}

/** 인증 토큰 서명. userId + email(가입 시점) 바인딩, 24h 만료. */
export function signEmailVerifyToken(
  secret: string,
  opts: { userId: string; email: string; ttlSec?: number; now?: number },
): string {
  const nowSec = Math.floor((opts.now ?? Date.now()) / 1000);
  const payload: EmailVerifyPayload = {
    sub: opts.userId,
    em: opts.email,
    exp: nowSec + (opts.ttlSec ?? DEFAULT_TTL_SEC),
  };
  const body = b64url(JSON.stringify(payload));
  return `${body}.${sign(secret, body)}`;
}

export type VerifyResult =
  | { ok: true; payload: EmailVerifyPayload }
  | { ok: false; reason: 'invalid' | 'expired' };

/**
 * 토큰 검증. 3-state(성공/만료/무효)를 반환한다(throw 아님) — 라우트가 HTML 페이지로 분기.
 * 서명 비교는 timingSafeEqual. 이메일 일치(사용자 존재) 확인은 호출자(라우트) 책임.
 */
export function verifyEmailVerifyToken(
  secret: string,
  token: string,
  opts: { now?: number } = {},
): VerifyResult {
  const parts = token.split('.');
  if (parts.length !== 2 || !parts[0] || !parts[1]) return { ok: false, reason: 'invalid' };
  const [body, sig] = parts;
  const expected = sign(secret, body);
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return { ok: false, reason: 'invalid' };

  let payload: EmailVerifyPayload;
  try {
    payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')) as EmailVerifyPayload;
  } catch {
    return { ok: false, reason: 'invalid' };
  }
  if (
    typeof payload.sub !== 'string' ||
    typeof payload.em !== 'string' ||
    typeof payload.exp !== 'number'
  ) {
    return { ok: false, reason: 'invalid' };
  }
  const nowSec = Math.floor((opts.now ?? Date.now()) / 1000);
  if (nowSec > payload.exp) return { ok: false, reason: 'expired' };
  return { ok: true, payload };
}

/** 인증 링크 URL 조립. base 끝 슬래시 정규화 + 토큰 URL 인코딩. */
export function buildVerifyUrl(baseUrl: string, token: string): string {
  return `${baseUrl.replace(/\/+$/, '')}/v1/auth/verify-email?token=${encodeURIComponent(token)}`;
}

// ── HTML (한국어, 양봉가 톤, 18px+, 꿀색) ─────────────────────────────────────

/** 인증 메일 본문 — 이메일 클라이언트에서 열림. 큰 버튼 + plain URL fallback + 24h 안내. */
export function buildVerificationEmailHtml(verifyUrl: string): string {
  const safeUrl = escapeHtml(verifyUrl);
  return `<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="margin:0;background:#FFFBF0;font-family:'Pretendard','Noto Sans KR',Apple SD Gothic Neo,sans-serif;color:#2A1F0E;">
  <div style="max-width:520px;margin:0 auto;padding:32px 24px;">
    <div style="font-size:26px;font-weight:700;color:#B0811E;margin-bottom:8px;">🐝 HelpBee</div>
    <div style="background:#ffffff;border-radius:24px;padding:32px 28px;box-shadow:0 4px 16px rgba(245,184,46,0.15);">
      <h1 style="font-size:24px;line-height:1.4;margin:0 0 16px;">이메일 인증을 완료해주세요</h1>
      <p style="font-size:18px;line-height:1.6;margin:0 0 24px;">
        HelpBee 가입을 환영합니다. 아래 버튼을 눌러 이메일 인증을 완료하시면
        벌통 사진 진단을 바로 이용하실 수 있어요.
      </p>
      <a href="${safeUrl}" style="display:inline-block;background:#F5B82E;color:#2A1F0E;font-size:19px;font-weight:700;text-decoration:none;padding:16px 32px;border-radius:16px;">
        이메일 인증하기
      </a>
      <p style="font-size:16px;line-height:1.6;color:#6B4423;margin:24px 0 4px;">
        버튼이 눌리지 않으면 아래 주소를 브라우저에 복사해 주세요:
      </p>
      <p style="font-size:15px;line-height:1.5;word-break:break-all;color:#6B4423;margin:0;">${safeUrl}</p>
      <p style="font-size:15px;line-height:1.6;color:#6B4423;margin:24px 0 0;">
        이 링크는 <b>24시간</b> 후 만료됩니다. 본인이 요청하지 않았다면 이 메일을 무시하셔도 됩니다.
      </p>
    </div>
  </div>
</body></html>`;
}

type VerifyState = 'success' | 'expired' | 'invalid';

/** 인증 결과 랜딩 페이지 — 이메일 클라이언트에서 링크 클릭 시 브라우저에 표시. */
export function renderVerifyEmailResultPage(state: VerifyState): string {
  const copy: Record<VerifyState, { emoji: string; title: string; body: string }> = {
    success: {
      emoji: '✅',
      title: '이메일 인증이 완료되었어요',
      body: '이제 HelpBee 앱으로 돌아가 벌통 진단을 시작하실 수 있습니다.',
    },
    expired: {
      emoji: '⏰',
      title: '인증 링크가 만료되었어요',
      body: '인증 링크는 24시간 동안만 유효합니다. 앱에서 인증 메일을 다시 요청해 주세요.',
    },
    invalid: {
      emoji: '⚠️',
      title: '인증 링크가 올바르지 않아요',
      body: '링크가 손상되었거나 이미 사용된 것 같아요. 앱에서 인증 메일을 다시 요청해 주세요.',
    },
  };
  const c = copy[state];
  return `<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>HelpBee 이메일 인증</title></head>
<body style="margin:0;background:#FFFBF0;font-family:'Pretendard','Noto Sans KR',Apple SD Gothic Neo,sans-serif;color:#2A1F0E;">
  <div style="max-width:480px;margin:0 auto;padding:48px 24px;text-align:center;">
    <div style="font-size:22px;font-weight:700;color:#B0811E;margin-bottom:24px;">🐝 HelpBee</div>
    <div style="background:#ffffff;border-radius:24px;padding:40px 28px;box-shadow:0 4px 16px rgba(245,184,46,0.15);">
      <div style="font-size:56px;line-height:1;margin-bottom:16px;">${c.emoji}</div>
      <h1 style="font-size:24px;line-height:1.4;margin:0 0 16px;">${escapeHtml(c.title)}</h1>
      <p style="font-size:18px;line-height:1.6;color:#6B4423;margin:0;">${escapeHtml(c.body)}</p>
    </div>
  </div>
</body></html>`;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Sender 추상화 ────────────────────────────────────────────────────────────

export type VerificationEmail = { to: string; verifyUrl: string };

export interface EmailSender {
  sendVerification(input: VerificationEmail): Promise<void>;
}

/** pino 호환 최소 로거 인터페이스(테스트에서 fake 주입). */
export type SenderLogger = {
  info(obj: Record<string, unknown>, msg?: string): void;
  warn(obj: Record<string, unknown>, msg?: string): void;
};

/** EMAIL_PROVIDER=console — 실제 발송 없이 인증 URL을 로그로 남긴다(로컬/개발). */
export class ConsoleSender implements EmailSender {
  constructor(private readonly log: SenderLogger) {}
  async sendVerification(input: VerificationEmail): Promise<void> {
    this.log.info(
      { to: input.to, verifyUrl: input.verifyUrl, provider: 'console' },
      '[email] verification link (console provider — no email actually sent)',
    );
  }
}

/**
 * EMAIL_PROVIDER=resend — Resend REST API(글로벌 fetch). 신규 npm 의존성 없음(Node 22).
 * 10s 타임아웃 + 5xx/네트워크 1회 재시도. 실패는 warn 로그 후 resolve(절대 throw 안 함).
 * 성공 시 Resend message id만 로그(키/본문 미로그).
 */
export class ResendSender implements EmailSender {
  constructor(
    private readonly cfg: {
      apiKey: string;
      from: string;
      log: SenderLogger;
      fetchImpl?: typeof fetch;
      timeoutMs?: number;
    },
  ) {}

  async sendVerification(input: VerificationEmail): Promise<void> {
    const fetchImpl = this.cfg.fetchImpl ?? fetch;
    const timeoutMs = this.cfg.timeoutMs ?? 10_000;
    const body = JSON.stringify({
      from: this.cfg.from,
      to: input.to,
      subject: SUBJECT,
      html: buildVerificationEmailHtml(input.verifyUrl),
    });

    for (let attempt = 0; attempt < 2; attempt++) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const res = await fetchImpl(RESEND_ENDPOINT, {
          method: 'POST',
          headers: {
            authorization: `Bearer ${this.cfg.apiKey}`,
            'content-type': 'application/json',
          },
          body,
          signal: controller.signal,
        });
        if (res.ok) {
          let id: string | null = null;
          try {
            id = ((await res.json()) as { id?: string }).id ?? null;
          } catch {
            /* body optional */
          }
          this.cfg.log.info(
            { to: input.to, messageId: id, provider: 'resend' },
            '[email] verification sent via Resend',
          );
          return;
        }
        if (res.status >= 500 && attempt === 0) continue; // 5xx → 1회 재시도
        let errText = '';
        try {
          errText = (await res.text()).slice(0, 500);
        } catch {
          /* ignore */
        }
        this.cfg.log.warn(
          { to: input.to, status: res.status, error: errText, provider: 'resend' },
          '[email] Resend rejected verification send',
        );
        return;
      } catch (err) {
        if (attempt === 0) continue; // 네트워크/타임아웃 → 1회 재시도
        this.cfg.log.warn(
          { to: input.to, error: err instanceof Error ? err.message : String(err), provider: 'resend' },
          '[email] Resend verification send failed',
        );
        return;
      } finally {
        clearTimeout(timer);
      }
    }
  }
}

/** EMAIL_PROVIDER 값으로 sender 선택. resend인데 키 없으면(방어적) console로 폴백. */
export function createEmailSender(cfg: {
  provider: 'console' | 'resend';
  resendApiKey?: string;
  from: string;
  log: SenderLogger;
}): EmailSender {
  if (cfg.provider === 'resend') {
    if (!cfg.resendApiKey) {
      cfg.log.warn({}, '[email] EMAIL_PROVIDER=resend but RESEND_API_KEY missing — falling back to console');
      return new ConsoleSender(cfg.log);
    }
    return new ResendSender({ apiKey: cfg.resendApiKey, from: cfg.from, log: cfg.log });
  }
  return new ConsoleSender(cfg.log);
}
