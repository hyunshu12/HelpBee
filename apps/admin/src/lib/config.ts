/** 서버 런타임 전용 설정. NEXT_PUBLIC_* 금지 — 절대 클라이언트 번들로 새지 않게. */

export const API_URL = process.env.API_URL ?? 'http://localhost:3001';

/** apps/api와 동일한 JWT 서명 시크릿. middleware의 서명/role 검증에만 사용. */
export function getJwtSecret(): Uint8Array {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET 환경변수가 설정되지 않았습니다 (apps/api와 동일 값).');
  }
  return new TextEncoder().encode(secret);
}

export const COOKIE_ACCESS = 'hb_admin_access';
export const COOKIE_REFRESH = 'hb_admin_refresh';
export const ACCESS_MAX_AGE = 900; // 15분
export const REFRESH_MAX_AGE = 60 * 60 * 24 * 7; // 7일
export const REFRESH_COOKIE_PATH = '/api';

export const isProd = process.env.NODE_ENV === 'production';
