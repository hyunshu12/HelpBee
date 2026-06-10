import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../lib/error-codes';
import { createAiClient, signInternalBearer, verifyInternalBearer } from './ai-client';

const SECRET = 'h'.repeat(32);

describe('signInternalBearer / verifyInternalBearer (D10)', () => {
  it('signs a verifiable token binding request_id + aud + exp', () => {
    const t = signInternalBearer(SECRET, { requestId: 'req-9', ttlSec: 300 });
    const p = verifyInternalBearer(SECRET, t);
    expect(p.request_id).toBe('req-9');
    expect(p.aud).toBe('ai');
    expect(p.exp).toBeGreaterThan(Math.floor(Date.now() / 1000));
  });

  it('rejects tampered token', () => {
    const t = signInternalBearer(SECRET, { requestId: 'r' });
    expect(() => verifyInternalBearer(SECRET, `${t}x`)).toThrow(AppError);
  });

  it('rejects wrong secret', () => {
    const t = signInternalBearer(SECRET, { requestId: 'r' });
    expect(() => verifyInternalBearer('o'.repeat(32), t)).toThrow();
  });

  it('rejects expired token', () => {
    const t = signInternalBearer(SECRET, { requestId: 'r', ttlSec: -10 });
    expect(() => verifyInternalBearer(SECRET, t)).toThrow();
  });
});

describe('createAiClient.analyze', () => {
  const aiResponse = {
    risk_score: 35,
    tier: 'watch',
    engine_used: 'yolo',
    recommendations: [],
    model_version: 'helpbee-yolov11s-0.1.0',
  };

  it('posts image_url + engine with signed bearer + request-id, returns data', async () => {
    const http = { post: vi.fn(async () => ({ data: aiResponse })) };
    const client = createAiClient({ baseURL: 'http://ai:8000', hmacSecret: SECRET, http });
    const res = await client.analyze({
      imageUrl: 'https://s3.example/key?sig=1',
      engine: 'auto',
      requestId: 'req-1',
    });
    expect(res.tier).toBe('watch');
    const [path, body, cfg] = http.post.mock.calls[0] as any;
    expect(path).toBe('/analyze');
    expect(body.image_url).toBe('https://s3.example/key?sig=1');
    expect(body.engine).toBe('auto');
    expect(cfg.headers.authorization).toMatch(/^Bearer /);
    expect(cfg.headers['x-request-id']).toBe('req-1');
    const token = cfg.headers.authorization.slice('Bearer '.length);
    expect(verifyInternalBearer(SECRET, token).request_id).toBe('req-1');
  });

  it('does NOT retry inference; throws AI_UNAVAILABLE once on transport error', async () => {
    const http = { post: vi.fn(async () => { throw new Error('ECONNREFUSED'); }) };
    const client = createAiClient({ baseURL: 'http://ai:8000', hmacSecret: SECRET, http });
    await expect(
      client.analyze({ imageUrl: 'u', engine: 'auto', requestId: 'r' }),
    ).rejects.toBeInstanceOf(AppError);
    expect(http.post).toHaveBeenCalledTimes(1); // 재시도 없음
  });
});
