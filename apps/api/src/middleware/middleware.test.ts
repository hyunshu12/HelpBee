import jwt from 'jwt-simple';
import { Hono } from 'hono';
import { describe, expect, it } from 'vitest';

import { requireAuth, requireRole } from './auth';
import { errorHandler } from './error-handler';
import { requestId } from './request-id';

const SECRET = 'x'.repeat(64);

function mint(payload: Record<string, unknown>, algorithm = 'HS256') {
  return jwt.encode({ exp: Math.floor(Date.now() / 1000) + 900, ...payload }, SECRET, algorithm);
}

function makeApp() {
  const app = new Hono();
  app.onError(errorHandler);
  app.use('*', requestId);
  app.get('/me', requireAuth(SECRET), (c) =>
    c.json({ userId: c.get('userId'), role: c.get('role') }),
  );
  app.get('/admin', requireAuth(SECRET), requireRole('admin'), (c) => c.json({ ok: true }));
  app.get('/boom', () => {
    throw new Error('unexpected');
  });
  return app;
}

describe('request-id', () => {
  it('generates an id and echoes header when absent', async () => {
    const res = await makeApp().request('/me', {
      headers: { authorization: `Bearer ${mint({ sub: 'u1', role: 'user' })}` },
    });
    expect(res.headers.get('x-request-id')).toBeTruthy();
  });

  it('keeps a valid incoming id', async () => {
    const res = await makeApp().request('/me', {
      headers: {
        authorization: `Bearer ${mint({ sub: 'u1', role: 'user' })}`,
        'x-request-id': 'incoming-abc-123',
      },
    });
    expect(res.headers.get('x-request-id')).toBe('incoming-abc-123');
  });
});

describe('requireAuth', () => {
  it('accepts a valid HS256 token and sets userId/role', async () => {
    const res = await makeApp().request('/me', {
      headers: { authorization: `Bearer ${mint({ sub: 'u1', role: 'user' })}` },
    });
    expect(res.status).toBe(200);
    expect((await res.json()).userId).toBe('u1');
  });

  it('401 when Authorization missing', async () => {
    const res = await makeApp().request('/me');
    expect(res.status).toBe(401);
    expect((await res.json()).code).toBe('AUTH_UNAUTHORIZED');
  });

  it('401 on wrong secret signature', async () => {
    const bad = jwt.encode({ sub: 'u1', exp: Math.floor(Date.now() / 1000) + 900 }, 'wrong'.repeat(20));
    const res = await makeApp().request('/me', { headers: { authorization: `Bearer ${bad}` } });
    expect(res.status).toBe(401);
  });

  it('401 AUTH_TOKEN_EXPIRED on expired token', async () => {
    const expired = jwt.encode({ sub: 'u1', exp: Math.floor(Date.now() / 1000) - 10 }, SECRET);
    const res = await makeApp().request('/me', { headers: { authorization: `Bearer ${expired}` } });
    expect(res.status).toBe(401);
    expect((await res.json()).code).toBe('AUTH_TOKEN_EXPIRED');
  });

  it('rejects alg confusion (token signed HS512, verifier pins HS256)', async () => {
    const hs512 = mint({ sub: 'u1', role: 'user' }, 'HS512');
    const res = await makeApp().request('/me', { headers: { authorization: `Bearer ${hs512}` } });
    expect(res.status).toBe(401);
  });
});

describe('requireRole', () => {
  it('admin passes', async () => {
    const res = await makeApp().request('/admin', {
      headers: { authorization: `Bearer ${mint({ sub: 'a1', role: 'admin' })}` },
    });
    expect(res.status).toBe(200);
  });

  it('403 FORBIDDEN_ROLE for non-admin', async () => {
    const res = await makeApp().request('/admin', {
      headers: { authorization: `Bearer ${mint({ sub: 'u1', role: 'user' })}` },
    });
    expect(res.status).toBe(403);
    expect((await res.json()).code).toBe('FORBIDDEN_ROLE');
  });
});

describe('error-handler', () => {
  it('maps unknown errors to INTERNAL 500 (masked)', async () => {
    const res = await makeApp().request('/boom');
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.code).toBe('INTERNAL');
    expect(body.detail).not.toContain('unexpected'); // 내부 메시지 노출 금지
  });
});
