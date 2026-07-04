/**
 * problem+json → 타입 있는 ApiError. code로 분기, 한국어 메시지 매핑(§7.3: detail 직접 노출 금지).
 */

export class ApiError extends Error {
  constructor(
    public code: string,
    public status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

/** 백엔드 error code → 사용자 노출 한국어 메시지. 미매핑은 기본 문구. */
const MESSAGES: Record<string, string> = {
  AUTH_INVALID_CREDENTIALS: '이메일 또는 비밀번호가 올바르지 않습니다.',
  AUTH_ACCOUNT_LOCKED: '로그인 시도가 많아 계정이 잠시 잠겼습니다. 잠시 후 다시 시도해 주세요.',
  FORBIDDEN_ROLE: '관리자 권한이 없는 계정입니다.',
  AUTH_UNAUTHORIZED: '로그인이 필요합니다.',
  AUTH_TOKEN_EXPIRED: '세션이 만료되었습니다. 다시 로그인해 주세요.',
  AUTH_REFRESH_INVALID: '세션이 만료되었습니다. 다시 로그인해 주세요.',
  REFRESH_REUSE_DETECTED: '보안을 위해 로그아웃되었습니다. 다시 로그인해 주세요.',
  RATE_LIMITED: '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.',
  NOT_FOUND: '요청한 데이터를 찾을 수 없습니다.',
  VALIDATION_FAILED: '입력값을 확인해 주세요.',
  ADMIN_SELF_DEMOTE_FORBIDDEN: '마지막 관리자는 강등할 수 없습니다.',
  AI_UNAVAILABLE: 'AI 서비스에 일시적으로 연결할 수 없습니다.',
  INTERNAL: '서버 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.',
};

export function messageForCode(code: string | undefined, fallback = '알 수 없는 오류가 발생했습니다.'): string {
  return (code && MESSAGES[code]) || fallback;
}
