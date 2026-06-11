/**
 * 구조화 로깅 (pino) (backend-design §7.2, §14.1).
 * 요청 완료 1줄: requestId/userId/method/route/status/latencyMs.
 * 민감 필드 redact 단일 목록(헤더/토큰/좌표/raw payload). 본 미들웨어는 큐레이션된 객체만
 * 로깅하므로 req.body/headers 통째 로깅 없음(누출 구조적 차단).
 */
import { createMiddleware } from 'hono/factory';
import { pino } from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  redact: {
    paths: [
      'authorization',
      'cookie',
      '["set-cookie"]', // 하이픈 키는 브래킷 표기(fast-redact 검증)
      'password',
      'passwordHash',
      'token',
      'refreshToken',
      'tokenHash',
      'uploadUrl',
      'latitude',
      'longitude',
      'address',
      'rawResponse',
      'raw_payload',
    ],
    censor: '[redacted]',
  },
});

export function loggerMiddleware() {
  return createMiddleware(async (c, next) => {
    const start = Date.now();
    await next();
    logger.info({
      requestId: c.get('requestId'),
      userId: c.get('userId'),
      method: c.req.method,
      route: c.req.path,
      status: c.res.status,
      latencyMs: Date.now() - start,
    });
  });
}
