import { createHmac } from 'node:crypto';

import { Hono } from 'hono';
import jwt from 'jwt-simple';
import { describe, expect, it } from 'vitest';

import { requireAdmin, requireAuth } from './auth';
import { errorHandler } from './error-handler';
import { rateLimit, type RateRedis } from './rate-limit';
import { requestId } from './request-id';
import { webhookSignatureGuard } from './webhook-signature';

const SECRET = 'x'.repeat(64);
const ADMIN_AUD = 'helpbee-admin';

function mint(payload: Record<string, unknown>) {
  return jwt.encode({ exp: Math.floor(Date.now() / 1000) + 900, ...payload }, SECRET, 'HS256');
}

function fakeRateRedis(): RateRedis & { fail?: boolean } {
  const store = new Map<string, number>();
  return {
    async incr(k: string) {
      const v = (store.get(k) ?? 0) + 1;
      store.set(k, v);
      return v;
    },
    async expire() {
      return 1;
    },
    async ttl() {
      return 60;
    },
  };
}

describe('rateLimit', () => {
  it('allows under limit, 429 over limit + Retry-After', async () => {
    const redis = fakeRateRedis();
    const app = new Hono();
    app.onError(errorHandler);
    app.use('*', requestId);
    app.use('*', rateLimit({ redis, limit: 2, windowSec: 60, prefix: 't', keyFn: () => 'ip1' }));
    app.get('/', (c) => c.text('ok'));
    expect((await app.request('/')).status).toBe(200);
    expect((await app.request('/')).status).toBe(200);
    const third = await app.request('/');
    expect(third.status).toBe(429);
    expect(third.headers.get('retry-after')).toBe('60');
  });

  it('fail-closed on Redis error (429)', async () => {
    const redis: RateRedis = {
      async incr() {
        throw new Error('redis down');
      },
      async expire() {
        return 1;
      },
      async ttl() {
        return 60;
      },
    };
    const app = new Hono();
    app.onError(errorHandler);
    app.use('*', requestId);
    app.use('*', rateLimit({ redis, limit: 100, windowSec: 60, prefix: 't', keyFn: () => 'ip' }));
    app.get('/', (c) => c.text('ok'));
    expect((await app.request('/')).status).toBe(429); // 가용성보다 남용 차단 우선
  });
});

describe('webhookSignatureGuard', () => {
  const SECRET_W = 'w'.repeat(40);
  function app(enabled: boolean, secret?: string) {
    const a = new Hono();
    a.onError(errorHandler);
    a.use('*', requestId);
    a.use('/wh', webhookSignatureGuard({ secret, enabled }));
    a.post('/wh', (c) => c.json({ body: c.get('webhookBody') }));
    return a;
  }
  function signed(secret: string, ts: string, body: string) {
    return createHmac('sha256', secret).update(`${ts}.${body}`).digest('hex');
  }

  it('503 WEBHOOK_DISABLED when disabled', async () => {
    const res = await app(false, SECRET_W).request('/wh', { method: 'POST', body: '{}' });
    expect(res.status).toBe(503);
    expect((await res.json()).code).toBe('WEBHOOK_DISABLED');
  });

  it('200 on valid signature + body passed', async () => {
    const ts = String(Math.floor(Date.now() / 1000));
    const body = '{"eventType":"x"}';
    const res = await app(true, SECRET_W).request('/wh', {
      method: 'POST',
      headers: { 'x-helpbee-signature': signed(SECRET_W, ts, body), 'x-helpbee-timestamp': ts },
      body,
    });
    expect(res.status).toBe(200);
    expect((await res.json()).body.eventType).toBe('x');
  });

  it('401 on bad signature', async () => {
    const ts = String(Math.floor(Date.now() / 1000));
    const res = await app(true, SECRET_W).request('/wh', {
      method: 'POST',
      headers: { 'x-helpbee-signature': 'deadbeef', 'x-helpbee-timestamp': ts },
      body: '{}',
    });
    expect(res.status).toBe(401);
    expect((await res.json()).code).toBe('WEBHOOK_SIGNATURE_INVALID');
  });

  it('401 on stale timestamp (replay window)', async () => {
    const stale = String(Math.floor(Date.now() / 1000) - 3600);
    const body = '{}';
    const res = await app(true, SECRET_W).request('/wh', {
      method: 'POST',
      headers: { 'x-helpbee-signature': signed(SECRET_W, stale, body), 'x-helpbee-timestamp': stale },
      body,
    });
    expect(res.status).toBe(401);
  });
});

describe('requireAdmin (role + audience, §17-4)', () => {
  function app() {
    const a = new Hono();
    a.onError(errorHandler);
    a.use('*', requestId);
    a.use('/admin', requireAuth(SECRET), requireAdmin(ADMIN_AUD));
    a.get('/admin', (c) => c.json({ ok: true }));
    return a;
  }

  it('200 for admin token with admin audience', async () => {
    const t = mint({ sub: 'a1', role: 'admin', aud: ADMIN_AUD, iat: Math.floor(Date.now() / 1000) });
    const res = await app().request('/admin', { headers: { authorization: `Bearer ${t}` } });
    expect(res.status).toBe(200);
  });

  it('403 for user token (BFLA)', async () => {
    const t = mint({ sub: 'u1', role: 'user', iat: Math.floor(Date.now() / 1000) });
    const res = await app().request('/admin', { headers: { authorization: `Bearer ${t}` } });
    expect(res.status).toBe(403);
    expect((await res.json()).code).toBe('FORBIDDEN_ROLE');
  });

  it('403 for admin role but missing/wrong audience (scope mismatch)', async () => {
    const t = mint({ sub: 'a1', role: 'admin', iat: Math.floor(Date.now() / 1000) }); // aud 없음
    const res = await app().request('/admin', { headers: { authorization: `Bearer ${t}` } });
    expect(res.status).toBe(403);
  });

  it('401 for anon (no token)', async () => {
    expect((await app().request('/admin')).status).toBe(401);
  });
});
