/**
 * x-request-id 생성/전파 (backend-design §7.1).
 * 인입 헤더가 유효 형식이면 채택, 아니면 생성. 응답 헤더로 echo + c.set('requestId').
 * AI 호출 시 동일 id 전파(분산 추적).
 */
import { randomUUID } from 'node:crypto';

import { createMiddleware } from 'hono/factory';

const VALID_ID = /^[A-Za-z0-9._-]{8,128}$/;

export const requestId = createMiddleware(async (c, next) => {
  const incoming = c.req.header('x-request-id');
  const id = incoming && VALID_ID.test(incoming) ? incoming : randomUUID();
  c.set('requestId', id);
  c.header('x-request-id', id);
  await next();
});
