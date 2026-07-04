/**
 * 에러 코드 단일 카탈로그 (backend-design §6.3).
 * code → {status, title}. 신규 에러는 반드시 여기 먼저 등록(자유 문자열 금지).
 * type URI는 code에서 kebab-case로 파생.
 *
 * 보안 규약(§13): 인가 실패(비소유 리소스)는 NOT_FOUND(404)로 존재 여부 누설 차단.
 * 명시적 role 부족만 FORBIDDEN_ROLE(403).
 */
export const ERROR_CATALOG = {
  VALIDATION_FAILED: { status: 400, title: 'Validation failed' },
  AUTH_INVALID_CREDENTIALS: { status: 401, title: 'Invalid credentials' },
  AUTH_TOKEN_EXPIRED: { status: 401, title: 'Token expired' },
  AUTH_UNAUTHORIZED: { status: 401, title: 'Unauthorized' },
  REFRESH_REUSE_DETECTED: { status: 401, title: 'Refresh token reuse detected' },
  AUTH_REFRESH_INVALID: { status: 401, title: 'Refresh invalid' },
  AUTH_EMAIL_TAKEN: { status: 409, title: 'Email already registered' },
  AUTH_ACCOUNT_LOCKED: { status: 429, title: 'Account locked' },
  AUTH_USER_NOT_FOUND: { status: 404, title: 'User not found' },
  AUTH_EMAIL_NOT_VERIFIED: { status: 403, title: 'Email not verified' },
  AUTH_EMAIL_ALREADY_VERIFIED: { status: 409, title: 'Email already verified' },
  FORBIDDEN: { status: 403, title: 'Forbidden' },
  FORBIDDEN_ROLE: { status: 403, title: 'Forbidden' },
  ADMIN_SELF_DEMOTE_FORBIDDEN: { status: 409, title: 'Cannot remove last admin' },
  NOT_FOUND: { status: 404, title: 'Resource not found' },
  UNSUPPORTED_MEDIA: { status: 415, title: 'Unsupported media type' },
  IMAGE_TOO_LARGE: { status: 413, title: 'Image too large' },
  IMAGE_INVALID: { status: 422, title: 'Invalid image' },
  IMAGE_NOT_FOUND_IN_STORAGE: { status: 404, title: 'Image not found in storage' },
  RATE_LIMITED: { status: 429, title: 'Too many requests' },
  QUOTA_EXCEEDED: { status: 402, title: 'Quota exceeded' },
  AI_UNAVAILABLE: { status: 503, title: 'AI engine unavailable' },
  AI_BUDGET_EXCEEDED: { status: 503, title: 'AI budget exceeded' },
  WEBHOOK_SIGNATURE_INVALID: { status: 401, title: 'Webhook signature invalid' },
  WEBHOOK_DISABLED: { status: 503, title: 'Webhook disabled' },
  INTERNAL: { status: 500, title: 'Internal server error' },
} as const;

export type ErrorCode = keyof typeof ERROR_CATALOG;

const ERROR_TYPE_BASE = 'https://helpbee.io/errors/';

export function errorType(code: ErrorCode): string {
  return ERROR_TYPE_BASE + code.toLowerCase().replace(/_/g, '-');
}

/** 라우트/서비스에서 throw → 전역 error-handler가 problem으로 정규화. */
export class AppError extends Error {
  constructor(
    public readonly code: ErrorCode,
    public readonly detail?: string,
    /** 429(잠금/레이트리밋) 시 Retry-After 헤더로 노출할 초. */
    public readonly retryAfterSec?: number,
  ) {
    super(code);
    this.name = 'AppError';
  }
}
