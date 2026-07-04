import { Hono } from 'hono';
import { describe, expect, it, vi } from 'vitest';

import { errorHandler } from '../middleware/error-handler';
import { rateLimit, type RateRedis } from '../middleware/rate-limit';
import { requestId } from '../middleware/request-id';
import { inquiriesRoutes, type InquiriesDeps } from './inquiries';

function makeApp(deps: InquiriesDeps) {
  const app = new Hono();
  app.onError(errorHandler);
  app.use('*', requestId);
  app.route('/', inquiriesRoutes(deps));
  return app;
}

const deps = (): InquiriesDeps => ({
  create: vi.fn(async () => ({ id: 'inq-1' })),
});

const post = (app: Hono, body: unknown) =>
  app.request('/', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

const valid = {
  name: '홍길동',
  email: 'hong@example.com',
  message: '벌통 진단 서비스에 대해 문의드립니다.',
  locale: 'ko',
};

describe('POST /v1/inquiries', () => {
  it('201 + id만 반환 (message echo 안 함)', async () => {
    const d = deps();
    const res = await post(makeApp(d), valid);
    expect(res.status).toBe(201);
    const { data } = await res.json();
    expect(data).toEqual({ id: 'inq-1' });
    expect(data.message).toBeUndefined();
    expect(d.create).toHaveBeenCalledWith({
      name: '홍길동',
      email: 'hong@example.com',
      message: '벌통 진단 서비스에 대해 문의드립니다.',
      locale: 'ko',
    });
  });

  it('locale 생략 시 null 전달', async () => {
    const d = deps();
    const { locale: _omit, ...noLocale } = valid;
    await post(makeApp(d), noLocale);
    expect(d.create).toHaveBeenCalledWith(expect.objectContaining({ locale: null }));
  });

  it('400 — message가 10자 미만', async () => {
    const d = deps();
    const res = await post(makeApp(d), { ...valid, message: '짧음' });
    expect(res.status).toBe(400);
    expect(d.create).not.toHaveBeenCalled();
  });

  it('400 — 잘못된 이메일', async () => {
    const d = deps();
    const res = await post(makeApp(d), { ...valid, email: 'not-an-email' });
    expect(res.status).toBe(400);
    expect(d.create).not.toHaveBeenCalled();
  });

  it('400 — 미지정 필드(strict)', async () => {
    const d = deps();
    const res = await post(makeApp(d), { ...valid, hiveId: 'x' });
    expect(res.status).toBe(400);
    expect(d.create).not.toHaveBeenCalled();
  });

  it('허니팟(website) 채워지면 201 위장 + DB 미저장', async () => {
    const d = deps();
    const res = await post(makeApp(d), { ...valid, website: 'http://spam.example' });
    expect(res.status).toBe(201);
    expect((await res.json()).data.id).toBeTruthy();
    expect(d.create).not.toHaveBeenCalled();
  });
});

describe('레이트리밋 (5/시간/IP) — 미들웨어 합성', () => {
  function makeRateLimitedApp(deps: InquiriesDeps) {
    const store = new Map<string, number>();
    const fakeRedis: RateRedis = {
      incr: async (k) => {
        const n = (store.get(k) ?? 0) + 1;
        store.set(k, n);
        return n;
      },
      expire: async () => 1,
      ttl: async () => 3600,
    };
    const app = new Hono();
    app.onError(errorHandler);
    app.use('*', requestId);
    app.use(
      '*',
      rateLimit({
        redis: fakeRedis,
        limit: 5,
        windowSec: 3600,
        prefix: 'inquiries',
        keyFn: () => 'ip-1',
      }),
    );
    app.route('/', inquiriesRoutes(deps));
    return app;
  }

  it('6번째 요청은 429 RATE_LIMITED', async () => {
    const app = makeRateLimitedApp(deps());
    for (let i = 0; i < 5; i++) {
      const res = await post(app, valid);
      expect(res.status).toBe(201);
    }
    const sixth = await post(app, valid);
    expect(sixth.status).toBe(429);
    expect((await sixth.json()).code).toBe('RATE_LIMITED');
    expect(sixth.headers.get('retry-after')).toBeTruthy();
  });
});
