import { Hono } from 'hono';
import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../lib/error-codes';
import { errorHandler } from '../middleware/error-handler';
import { requestId } from '../middleware/request-id';
import { adminRoutes, type AdminDeps, type DualRow } from './admin';

const UID = '00000000-0000-4000-8000-000000000001';

function makeDeps(over: Partial<AdminDeps> = {}): AdminDeps {
  return {
    listUsers: vi.fn(async () => ({ rows: [{ id: UID, email: 'a@b.com', role: 'user' }], total: 1 })),
    patchUser: vi.fn(async () => ({ detail: { id: UID, role: 'admin' }, blockedNow: false })),
    onBlocked: vi.fn(async () => undefined),
    listAuditLogs: vi.fn(async () => ({ rows: [{ id: '5', action: 'auth.login' }], nextCursor: null })),
    metrics: vi.fn(async () => ({ users: { total: 3 } })),
    getDualByImage: vi.fn(async () => []),
    ...over,
  };
}

function makeApp(deps: AdminDeps, actorId = 'admin1') {
  const app = new Hono();
  app.onError(errorHandler);
  app.use('*', requestId);
  app.use('*', async (c, next) => {
    c.set('userId', actorId);
    c.set('role', 'admin');
    await next();
  });
  app.route('/', adminRoutes(deps));
  return app;
}

function json(app: Hono, method: string, path: string, body?: unknown) {
  return app.request(path, {
    method,
    headers: { 'content-type': 'application/json' },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
}

describe('GET /admin/users', () => {
  it('200 list + pagination', async () => {
    const res = await makeApp(makeDeps()).request('/users?page=1&pageSize=20');
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data).toHaveLength(1);
    expect(body.meta.pagination).toEqual({ limit: 20, offset: 0, total: 1 });
  });

  it('400 pageSize > 100', async () => {
    expect((await makeApp(makeDeps()).request('/users?pageSize=101')).status).toBe(400);
  });
});

describe('PATCH /admin/users/:id', () => {
  it('200 on role change', async () => {
    const deps = makeDeps();
    const res = await json(makeApp(deps), 'PATCH', `/users/${UID}`, { role: 'admin' });
    expect(res.status).toBe(200);
    expect(deps.patchUser).toHaveBeenCalledWith(expect.objectContaining({ role: 'admin', actorId: 'admin1' }));
  });

  it('404 when user not found', async () => {
    const deps = makeDeps({ patchUser: vi.fn(async () => undefined) });
    const res = await json(makeApp(deps), 'PATCH', `/users/${UID}`, { status: 'blocked' });
    expect(res.status).toBe(404);
  });

  it('409 ADMIN_SELF_DEMOTE_FORBIDDEN (adapter가 AppError throw)', async () => {
    const deps = makeDeps({
      patchUser: vi.fn(async () => {
        throw new AppError('ADMIN_SELF_DEMOTE_FORBIDDEN');
      }),
    });
    const res = await json(makeApp(deps), 'PATCH', `/users/${UID}`, { role: 'user' });
    expect(res.status).toBe(409);
    expect((await res.json()).code).toBe('ADMIN_SELF_DEMOTE_FORBIDDEN');
  });

  it('blockedNow → onBlocked 호출(즉시 회수)', async () => {
    const deps = makeDeps({
      patchUser: vi.fn(async () => ({ detail: { id: UID }, blockedNow: true })),
    });
    await json(makeApp(deps), 'PATCH', `/users/${UID}`, { status: 'blocked' });
    expect(deps.onBlocked).toHaveBeenCalledWith(UID);
  });

  it('400 empty body / unknown key (.strict)', async () => {
    expect((await json(makeApp(makeDeps()), 'PATCH', `/users/${UID}`, {})).status).toBe(400);
    expect(
      (await json(makeApp(makeDeps()), 'PATCH', `/users/${UID}`, { foo: 'bar' })).status,
    ).toBe(400);
  });
});

describe('GET /admin/audit-logs', () => {
  it('200 items + nextCursor', async () => {
    const res = await makeApp(makeDeps()).request('/audit-logs?limit=50');
    expect(res.status).toBe(200);
    const { data } = await res.json();
    expect(data.items).toHaveLength(1);
    expect(data.nextCursor).toBeNull();
  });
});

describe('GET /admin/analyses/:imageId/dual', () => {
  const IMG = '00000000-0000-4000-8000-0000000000b1';
  function dualRow(over: Partial<DualRow> = {}): DualRow {
    return {
      provider: 'yolo',
      modelName: 'helpbee-yolov11s',
      modelVersion: '0.1.0',
      status: 'success',
      varroaInfectionRisk: 35,
      overallHealth: 'warning',
      rawResponse: { boxes: 7, score: 0.8, gps: '37.5,127', source_url: 'https://x' },
      ...over,
    };
  }

  it('404 when no rows', async () => {
    expect((await makeApp(makeDeps()).request(`/analyses/${IMG}/dual`)).status).toBe(404);
  });

  it('200 single row → secondary null; raw 화이트리스트(URL/GPS drop)', async () => {
    const deps = makeDeps({ getDualByImage: vi.fn(async () => [dualRow()]) });
    const { data } = await (await makeApp(deps).request(`/analyses/${IMG}/dual`)).json();
    expect(data.secondary).toBeNull();
    expect(data.agreement).toBeNull();
    expect(data.primary.rawResponse).toEqual({ boxes: 7, score: 0.8 }); // gps/source_url 제거
  });

  it('200 dual → agreement(healthMatch/riskDiff)', async () => {
    const deps = makeDeps({
      getDualByImage: vi.fn(async () => [
        dualRow({ provider: 'yolo', varroaInfectionRisk: 35, overallHealth: 'warning' }),
        dualRow({ provider: 'openai', varroaInfectionRisk: 50, overallHealth: 'warning' }),
      ]),
    });
    const { data } = await (await makeApp(deps).request(`/analyses/${IMG}/dual`)).json();
    expect(data.primary.provider).toBe('yolo'); // 사용 엔진
    expect(data.secondary.provider).toBe('openai');
    expect(data.agreement).toEqual({ healthMatch: true, riskDiff: 15 });
  });
});
