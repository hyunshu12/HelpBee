/**
 * 성공 응답 봉투 {data, meta} (backend-design §6.1).
 * 라우트는 raw c.json 대신 ok()/created()만 사용. requestId/timestamp는 자동.
 */
import type { Context } from 'hono';

export type Pagination = { limit: number; offset: number; total: number };
export type Meta = {
  requestId: string;
  timestamp: string;
  pagination?: Pagination;
};

function buildMeta(c: Context, extra?: Partial<Meta>): Meta {
  return {
    requestId: (c.get('requestId') as string | undefined) ?? '',
    timestamp: new Date().toISOString(),
    ...extra,
  };
}

export function ok<T>(c: Context, data: T, extra?: Partial<Meta>) {
  return c.json({ data, meta: buildMeta(c, extra) }, 200);
}

export function created<T>(c: Context, data: T, extra?: Partial<Meta>) {
  return c.json({ data, meta: buildMeta(c, extra) }, 201);
}
