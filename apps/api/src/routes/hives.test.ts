import { Hono } from 'hono';
import { describe, expect, it, vi } from 'vitest';

import { errorHandler } from '../middleware/error-handler';
import { requestId } from '../middleware/request-id';
import { hivesRoutes, type HivesDeps } from './hives';

const HIVE = { id: 'h1', userId: 'u1', name: 'H', note: null, latitude: null, longitude: null };

function makeDeps(over: Partial<HivesDeps> = {}): HivesDeps {
  return {
    list: vi.fn(async () => [HIVE]),
    create: vi.fn(async (_u, i) => ({ id: 'new', ...i })),
    getById: vi.fn(async () => HIVE),
    update: vi.fn(async (_id, _u, p) => ({ ...HIVE, ...p })),
    softDelete: vi.fn(async () => ({ id: 'h1', deletedAt: new Date('2026-06-11T00:00:00Z') })),
    cacheGet: vi.fn(async () => null),
    cacheSet: vi.fn(async () => undefined),
    cacheInvalidate: vi.fn(async () => undefined),
    audit: vi.fn(async () => undefined),
    ...over,
  };
}

function makeApp(deps: HivesDeps, userId = 'u1') {
  const app = new Hono();
  app.onError(errorHandler);
  app.use('*', requestId);
  app.use('*', async (c, next) => {
    c.set('userId', userId);
    await next();
  });
  app.route('/', hivesRoutes(deps));
  return app;
}

function json(app: Hono, method: string, path: string, body?: unknown) {
  return app.request(path, {
    method,
    headers: { 'content-type': 'application/json' },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
}

describe('GET /hives', () => {
  it('200 list + pagination meta; default page caches (miss→db→set)', async () => {
    const deps = makeDeps();
    const res = await makeApp(deps).request('/');
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data).toHaveLength(1);
    expect(body.meta.pagination).toEqual({ limit: 50, offset: 0, total: 1 });
    expect(deps.cacheGet).toHaveBeenCalledOnce();
    expect(deps.cacheSet).toHaveBeenCalledOnce();
  });

  it('default page cache hit → no DB call', async () => {
    const deps = makeDeps({ cacheGet: vi.fn(async () => [HIVE, HIVE]) });
    const res = await makeApp(deps).request('/');
    expect(res.status).toBe(200);
    expect((await res.json()).data).toHaveLength(2);
    expect(deps.list).not.toHaveBeenCalled();
  });

  it('non-default page bypasses cache', async () => {
    const deps = makeDeps();
    await makeApp(deps).request('/?limit=10&offset=20');
    expect(deps.cacheGet).not.toHaveBeenCalled();
    expect(deps.list).toHaveBeenCalledWith('u1', { limit: 10, offset: 20 });
  });

  it('400 on limit > 100', async () => {
    const res = await makeApp(makeDeps()).request('/?limit=101');
    expect(res.status).toBe(400);
  });
});

describe('POST /hives', () => {
  it('201 + cache invalidate', async () => {
    const deps = makeDeps();
    const res = await json(makeApp(deps), 'POST', '/', { name: '새 벌통' });
    expect(res.status).toBe(201);
    expect(deps.cacheInvalidate).toHaveBeenCalledWith('u1');
  });

  it('400 half-coordinate (lat without lng)', async () => {
    const res = await json(makeApp(makeDeps()), 'POST', '/', { name: 'x', latitude: 37.5 });
    expect(res.status).toBe(400);
  });

  it('400 Mass Assignment (userId injection — .strict)', async () => {
    const res = await json(makeApp(makeDeps()), 'POST', '/', { name: 'x', userId: 'attacker' });
    expect(res.status).toBe(400);
  });
});

describe('GET /hives/:id (IDOR)', () => {
  it('200 when owned', async () => {
    const res = await makeApp(makeDeps()).request('/00000000-0000-4000-8000-000000000001');
    expect(res.status).toBe(200);
  });

  it('404 when not owned (deps returns undefined) — 존재 누설 X', async () => {
    const deps = makeDeps({ getById: vi.fn(async () => undefined) });
    const res = await makeApp(deps).request('/00000000-0000-4000-8000-000000000099');
    expect(res.status).toBe(404);
    expect((await res.json()).code).toBe('NOT_FOUND');
  });

  it('400 on non-uuid id', async () => {
    const res = await makeApp(makeDeps()).request('/not-a-uuid');
    expect(res.status).toBe(400);
  });
});

describe('PATCH /hives/:id', () => {
  const ID = '00000000-0000-4000-8000-000000000001';
  it('200 update + invalidate', async () => {
    const deps = makeDeps();
    const res = await json(makeApp(deps), 'PATCH', `/${ID}`, { name: '수정' });
    expect(res.status).toBe(200);
    expect(deps.cacheInvalidate).toHaveBeenCalled();
  });

  it('404 when not owned', async () => {
    const deps = makeDeps({ update: vi.fn(async () => undefined) });
    const res = await json(makeApp(deps), 'PATCH', `/${ID}`, { name: 'x' });
    expect(res.status).toBe(404);
  });

  it('400 empty patch', async () => {
    const res = await json(makeApp(makeDeps()), 'PATCH', `/${ID}`, {});
    expect(res.status).toBe(400);
  });

  it('400 Mass Assignment (deleted_at injection)', async () => {
    const res = await json(makeApp(makeDeps()), 'PATCH', `/${ID}`, { deletedAt: null, name: 'x' });
    expect(res.status).toBe(400);
  });
});

describe('DELETE /hives/:id (soft delete)', () => {
  const ID = '00000000-0000-4000-8000-000000000001';
  it('200 + deletedAt + invalidate + audit', async () => {
    const deps = makeDeps();
    const res = await json(makeApp(deps), 'DELETE', `/${ID}`);
    expect(res.status).toBe(200);
    expect((await res.json()).data.deletedAt).toBeTruthy();
    expect(deps.cacheInvalidate).toHaveBeenCalled();
    expect(deps.audit).toHaveBeenCalledWith(expect.objectContaining({ action: 'hive.deleted' }));
  });

  it('404 when not owned (no audit, no invalidate)', async () => {
    const deps = makeDeps({ softDelete: vi.fn(async () => undefined) });
    const res = await json(makeApp(deps), 'DELETE', `/${ID}`);
    expect(res.status).toBe(404);
    expect(deps.audit).not.toHaveBeenCalled();
  });
});
