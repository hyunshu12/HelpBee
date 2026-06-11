/**
 * Webhook HMAC 서명 검증 (backend-design §7.6, §11.4).
 * - raw body(파싱 전 bytes)로 HMAC-SHA256, timingSafeEqual 상수시간 비교.
 * - 타임스탬프 ±윈도(replay 차단). zValidator보다 먼저(라우트 최상단).
 * - 시크릿 미구성/비활성 → WEBHOOK_DISABLED(503, fail-closed).
 * 검증 통과 시 파싱된 body를 c.set('webhookBody')로 전달(핸들러는 zValidator 미사용).
 */
import { createHmac, timingSafeEqual } from 'node:crypto';

import { createMiddleware } from 'hono/factory';

import { AppError } from '../lib/error-codes';

function safeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  try {
    return timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
  } catch {
    return false;
  }
}

export function webhookSignatureGuard(opts: {
  secret?: string;
  enabled: boolean;
  toleranceSec?: number;
  now?: () => number;
}) {
  const tolerance = opts.toleranceSec ?? 300;
  const now = opts.now ?? (() => Date.now());
  return createMiddleware(async (c, next) => {
    if (!opts.enabled || !opts.secret) {
      throw new AppError('WEBHOOK_DISABLED');
    }
    const signature = c.req.header('x-helpbee-signature');
    const timestamp = c.req.header('x-helpbee-timestamp');
    if (!signature || !timestamp) {
      throw new AppError('WEBHOOK_SIGNATURE_INVALID', 'missing signature headers');
    }
    const tsNum = Number(timestamp);
    if (!Number.isFinite(tsNum) || Math.abs(now() / 1000 - tsNum) > tolerance) {
      throw new AppError('WEBHOOK_SIGNATURE_INVALID', 'timestamp outside window');
    }
    const raw = await c.req.text(); // raw body — 파싱 전
    const expected = createHmac('sha256', opts.secret).update(`${timestamp}.${raw}`).digest('hex');
    if (!safeEqualHex(signature, expected)) {
      throw new AppError('WEBHOOK_SIGNATURE_INVALID', 'signature mismatch');
    }
    let body: unknown = {};
    if (raw) {
      try {
        body = JSON.parse(raw);
      } catch {
        throw new AppError('WEBHOOK_SIGNATURE_INVALID', 'invalid json body');
      }
    }
    c.set('webhookBody', body);
    await next();
  });
}
