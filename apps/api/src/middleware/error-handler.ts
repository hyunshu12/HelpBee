/**
 * 전역 에러 핸들러 (backend-design §6.2, §7.8, §13).
 * AppError → 매핑된 problem. ZodError → VALIDATION_FAILED(path만 노출).
 * 그 외 미분류 예외 → INTERNAL(500), 내부 메시지/스택 노출 금지(Sentry로만).
 */
import type { ErrorHandler } from 'hono';
import { ZodError } from 'zod';

import { AppError } from '../lib/error-codes';
import { problem } from '../lib/problem';

export const errorHandler: ErrorHandler = (err, c) => {
  if (err instanceof AppError) {
    return problem(c, err.code, err.detail);
  }
  if (err instanceof ZodError) {
    const paths = err.issues.map((i) => i.path.join('.')).filter(Boolean);
    return problem(c, 'VALIDATION_FAILED', paths.join(', ') || undefined);
  }
  // 미분류 예외: 입력값/스택/내부 메시지 노출 금지. (관측은 §14 Sentry/pino)
  return problem(c, 'INTERNAL');
};
