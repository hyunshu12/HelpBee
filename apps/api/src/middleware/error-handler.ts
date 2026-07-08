/**
 * 전역 에러 핸들러 (backend-design §6.2, §7.8, §13).
 * AppError → 매핑된 problem. ZodError → VALIDATION_FAILED(path만 노출).
 * 그 외 미분류 예외 → INTERNAL(500), 내부 메시지/스택 노출 금지(Sentry로만).
 */
import type { ErrorHandler } from 'hono';
import { ZodError } from 'zod';

import { AppError } from '../lib/error-codes';
import { problem } from '../lib/problem';
import { captureException } from '../lib/sentry';

export const errorHandler: ErrorHandler = (err, c) => {
  if (err instanceof AppError) {
    return problem(c, err.code, err.detail, { retryAfterSec: err.retryAfterSec });
  }
  if (err instanceof ZodError) {
    const paths = err.issues.map((i) => i.path.join('.')).filter(Boolean);
    return problem(c, 'VALIDATION_FAILED', paths.join(', ') || undefined);
  }
  // 미분류 예외: HTTP 응답엔 입력값/스택/내부 메시지 노출 금지(§13.4). 단 서버측 관측은 필수 —
  // 그렇지 않으면 500이 흔적 없이 사라진다. pino 전환 전까지 stderr로 stack+requestId 남김(§14).
  const requestId = c.get('requestId') ?? c.req.header('x-request-id') ?? '-';
  captureException(err, { requestId, route: `${c.req.method} ${c.req.path}` });
  console.error(
    JSON.stringify({
      level: 'error',
      msg: 'unhandled_exception',
      requestId,
      route: `${c.req.method} ${c.req.path}`,
    }),
    err,
  );
  return problem(c, 'INTERNAL');
};
