import { Hono } from 'hono';
import { describe, expect, it } from 'vitest';

import { ERROR_CATALOG, errorType } from './error-codes';
import { created, ok } from './envelope';
import { problem } from './problem';

function appWith(handler: (c: any) => Response | Promise<Response>) {
  const a = new Hono();
  a.use('*', async (c, next) => {
    c.set('requestId', 'req-1');
    await next();
  });
  a.get('/t', handler);
  return a;
}

describe('envelope', () => {
  it('ok() wraps {data, meta} with requestId + timestamp', async () => {
    const res = await appWith((c) => ok(c, { x: 1 })).request('/t');
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data).toEqual({ x: 1 });
    expect(body.meta.requestId).toBe('req-1');
    expect(typeof body.meta.timestamp).toBe('string');
  });

  it('created() → 201', async () => {
    const res = await appWith((c) => created(c, { id: 'a' })).request('/t');
    expect(res.status).toBe(201);
    expect((await res.json()).data).toEqual({ id: 'a' });
  });

  it('ok() carries pagination meta', async () => {
    const res = await appWith((c) =>
      ok(c, [1, 2], { pagination: { limit: 50, offset: 0, total: 2 } }),
    ).request('/t');
    expect((await res.json()).meta.pagination.total).toBe(2);
  });
});

describe('problem (RFC 7807)', () => {
  it('emits problem+json with code/status/type/requestId', async () => {
    const res = await appWith((c) => problem(c, 'QUOTA_EXCEEDED', 'limit reached')).request('/t');
    expect(res.status).toBe(402);
    expect(res.headers.get('content-type')).toContain('application/problem+json');
    const body = await res.json();
    expect(body.code).toBe('QUOTA_EXCEEDED');
    expect(body.status).toBe(402);
    expect(body.requestId).toBe('req-1');
    expect(body.instance).toBe('/t');
    expect(body.type).toBe(errorType('QUOTA_EXCEEDED'));
    expect(body.detail).toBe('limit reached');
  });

  it('detail defaults to title when omitted', async () => {
    const res = await appWith((c) => problem(c, 'NOT_FOUND')).request('/t');
    const body = await res.json();
    expect(body.detail).toBe('Resource not found');
  });
});

describe('error-codes', () => {
  it('NOT_FOUND is 404 (IDOR 누설 차단용 공통 코드)', () => {
    expect(ERROR_CATALOG.NOT_FOUND.status).toBe(404);
  });
  it('QUOTA_EXCEEDED is 402', () => {
    expect(ERROR_CATALOG.QUOTA_EXCEEDED.status).toBe(402);
  });
  it('errorType is kebab-cased URI', () => {
    expect(errorType('REFRESH_REUSE_DETECTED')).toBe(
      'https://helpbee.io/errors/refresh-reuse-detected',
    );
  });
});
