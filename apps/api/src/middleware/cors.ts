/**
 * CORS — allowlist 정확 매칭 (backend-design §7.3, §13 API8).
 * 와일드카드 `*`/origin 무조건 echo 금지. allowlist에 매칭될 때만 그 origin 반환 + credentials.
 */
import { cors } from 'hono/cors';

export function corsMiddleware(allowlist: string[]) {
  return cors({
    origin: (origin) => (origin && allowlist.includes(origin) ? origin : null),
    credentials: true,
    allowMethods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowHeaders: ['authorization', 'content-type', 'x-request-id'],
    maxAge: 600,
  });
}
