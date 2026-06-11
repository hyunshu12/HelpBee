/**
 * RFC 7807 Problem Details (backend-design §6.2).
 * Content-Type: application/problem+json. raw c.json 금지 — 이 헬퍼만 사용.
 * detail에 사용자 입력/PII/secret 반사 금지.
 */
import type { Context } from 'hono';

import { ERROR_CATALOG, errorType, type ErrorCode } from './error-codes';

export function problem(
  c: Context,
  code: ErrorCode,
  detail?: string,
  opts?: { retryAfterSec?: number },
) {
  const { status, title } = ERROR_CATALOG[code];
  const requestId = (c.get('requestId') as string | undefined) ?? '';
  const payload = {
    type: errorType(code),
    title,
    status,
    code,
    detail: detail ?? title,
    instance: c.req.path,
    requestId,
  };
  const headers: Record<string, string> = { 'content-type': 'application/problem+json' };
  if (opts?.retryAfterSec != null && opts.retryAfterSec > 0) {
    headers['retry-after'] = String(Math.ceil(opts.retryAfterSec));
  }
  return c.json(payload, status as never, headers);
}
