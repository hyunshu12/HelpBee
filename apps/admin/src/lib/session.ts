/**
 * 서버 전용 세션 쿠키 헬퍼. httpOnly 쿠키로 토큰을 저장해 브라우저 JS에 노출하지 않는다(§4-2).
 * access=hb_admin_access(15m), refresh=hb_admin_refresh(7d, path=/api).
 */
import type { NextResponse } from 'next/server';

import {
  ACCESS_MAX_AGE,
  COOKIE_ACCESS,
  COOKIE_REFRESH,
  isProd,
  REFRESH_COOKIE_PATH,
  REFRESH_MAX_AGE,
} from './config';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export function setSessionCookies(res: NextResponse, tokens: TokenPair): void {
  res.cookies.set(COOKIE_ACCESS, tokens.accessToken, {
    httpOnly: true,
    secure: isProd,
    sameSite: 'lax',
    path: '/',
    maxAge: ACCESS_MAX_AGE,
  });
  res.cookies.set(COOKIE_REFRESH, tokens.refreshToken, {
    httpOnly: true,
    secure: isProd,
    sameSite: 'lax',
    path: REFRESH_COOKIE_PATH,
    maxAge: REFRESH_MAX_AGE,
  });
}

export function clearSessionCookies(res: NextResponse): void {
  res.cookies.set(COOKIE_ACCESS, '', { httpOnly: true, path: '/', maxAge: 0 });
  res.cookies.set(COOKIE_REFRESH, '', { httpOnly: true, path: REFRESH_COOKIE_PATH, maxAge: 0 });
}
