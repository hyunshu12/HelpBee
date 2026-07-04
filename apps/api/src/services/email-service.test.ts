import { describe, expect, it, vi } from 'vitest';

import {
  ConsoleSender,
  ResendSender,
  buildVerifyUrl,
  createEmailSender,
  renderVerifyEmailResultPage,
  signEmailVerifyToken,
  verifyEmailVerifyToken,
  type SenderLogger,
} from './email-service';

const SECRET = 's'.repeat(64);

function fakeLogger() {
  return { info: vi.fn(), warn: vi.fn() } satisfies SenderLogger;
}

describe('email verify token (HMAC, stateless)', () => {
  it('round-trips userId + email', () => {
    const t = signEmailVerifyToken(SECRET, { userId: 'u1', email: 'a@b.com' });
    const r = verifyEmailVerifyToken(SECRET, t);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.payload.sub).toBe('u1');
      expect(r.payload.em).toBe('a@b.com');
    }
  });

  it('reports expired for past exp', () => {
    const t = signEmailVerifyToken(SECRET, { userId: 'u1', email: 'a@b.com', ttlSec: -10 });
    const r = verifyEmailVerifyToken(SECRET, t);
    expect(r).toEqual({ ok: false, reason: 'expired' });
  });

  it('rejects tampered signature as invalid', () => {
    const t = signEmailVerifyToken(SECRET, { userId: 'u1', email: 'a@b.com' });
    const r = verifyEmailVerifyToken(SECRET, `${t}x`);
    expect(r).toEqual({ ok: false, reason: 'invalid' });
  });

  it('rejects token signed with a different secret', () => {
    const t = signEmailVerifyToken('o'.repeat(64), { userId: 'u1', email: 'a@b.com' });
    expect(verifyEmailVerifyToken(SECRET, t)).toEqual({ ok: false, reason: 'invalid' });
  });

  it('rejects malformed token', () => {
    expect(verifyEmailVerifyToken(SECRET, 'not-a-token')).toEqual({ ok: false, reason: 'invalid' });
  });

  it('email-mismatch is detectable via payload.em (binding)', () => {
    const t = signEmailVerifyToken(SECRET, { userId: 'u1', email: 'old@b.com' });
    const r = verifyEmailVerifyToken(SECRET, t);
    expect(r.ok && r.payload.em).toBe('old@b.com'); // route compares against current email
  });
});

describe('buildVerifyUrl', () => {
  it('normalizes trailing slash + encodes token', () => {
    const url = buildVerifyUrl('http://localhost:3001/', 'a.b+c');
    expect(url).toBe('http://localhost:3001/v1/auth/verify-email?token=a.b%2Bc');
  });
});

describe('renderVerifyEmailResultPage', () => {
  it('renders 3 states as Korean HTML', () => {
    expect(renderVerifyEmailResultPage('success')).toContain('인증이 완료');
    expect(renderVerifyEmailResultPage('expired')).toContain('만료');
    expect(renderVerifyEmailResultPage('invalid')).toContain('올바르지 않');
  });
});

describe('ConsoleSender', () => {
  it('logs the verify URL, never throws', async () => {
    const log = fakeLogger();
    await new ConsoleSender(log).sendVerification({ to: 'a@b.com', verifyUrl: 'http://x/verify' });
    expect(log.info).toHaveBeenCalledOnce();
    const [obj] = log.info.mock.calls[0]!;
    expect(obj).toMatchObject({ to: 'a@b.com', verifyUrl: 'http://x/verify', provider: 'console' });
  });
});

describe('ResendSender', () => {
  function okResponse(id = 'msg_123') {
    return { ok: true, status: 200, json: async () => ({ id }), text: async () => '' } as Response;
  }
  function errResponse(status: number, body = 'err') {
    return { ok: false, status, json: async () => ({}), text: async () => body } as Response;
  }

  it('POSTs to Resend and logs only message id on 200', async () => {
    const fetchImpl = vi.fn(async () => okResponse('msg_abc'));
    const log = fakeLogger();
    await new ResendSender({ apiKey: 'k', from: 'HelpBee <x@y>', log, fetchImpl }).sendVerification({
      to: 'a@b.com',
      verifyUrl: 'http://x/verify',
    });
    expect(fetchImpl).toHaveBeenCalledOnce();
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://api.resend.com/emails');
    expect(init.method).toBe('POST');
    expect(init.headers).toMatchObject({ authorization: 'Bearer k' });
    expect(log.info).toHaveBeenCalledOnce();
    expect(log.info.mock.calls[0]![0]).toMatchObject({ messageId: 'msg_abc' });
  });

  it('retries once on 5xx then succeeds', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(errResponse(503))
      .mockResolvedValueOnce(okResponse());
    const log = fakeLogger();
    await new ResendSender({ apiKey: 'k', from: 'f', log, fetchImpl }).sendVerification({
      to: 'a@b.com',
      verifyUrl: 'u',
    });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(log.info).toHaveBeenCalledOnce();
  });

  it('warns and resolves (never throws) on 4xx', async () => {
    const fetchImpl = vi.fn(async () => errResponse(403, 'domain not verified'));
    const log = fakeLogger();
    await expect(
      new ResendSender({ apiKey: 'k', from: 'f', log, fetchImpl }).sendVerification({
        to: 'a@b.com',
        verifyUrl: 'u',
      }),
    ).resolves.toBeUndefined();
    expect(fetchImpl).toHaveBeenCalledOnce(); // 4xx = no retry
    expect(log.warn).toHaveBeenCalledOnce();
  });

  it('retries once on network error then warns, resolves', async () => {
    const fetchImpl = vi.fn(async () => {
      throw new Error('ECONNRESET');
    });
    const log = fakeLogger();
    await expect(
      new ResendSender({ apiKey: 'k', from: 'f', log, fetchImpl }).sendVerification({
        to: 'a@b.com',
        verifyUrl: 'u',
      }),
    ).resolves.toBeUndefined();
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(log.warn).toHaveBeenCalledOnce();
  });
});

describe('createEmailSender', () => {
  it('returns ConsoleSender for provider=console', () => {
    expect(createEmailSender({ provider: 'console', from: 'f', log: fakeLogger() })).toBeInstanceOf(
      ConsoleSender,
    );
  });

  it('returns ResendSender when provider=resend + key present', () => {
    expect(
      createEmailSender({ provider: 'resend', resendApiKey: 'k', from: 'f', log: fakeLogger() }),
    ).toBeInstanceOf(ResendSender);
  });

  it('falls back to ConsoleSender when provider=resend but key missing', () => {
    const log = fakeLogger();
    expect(createEmailSender({ provider: 'resend', from: 'f', log })).toBeInstanceOf(ConsoleSender);
    expect(log.warn).toHaveBeenCalledOnce();
  });
});
