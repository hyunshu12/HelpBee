/**
 * 인증 가드. /login·/api/session·정적 자원을 제외한 모든 경로 보호(§4-3).
 * 정책(단순·안전 우선):
 *  - access 쿠키 없음 → /login
 *  - access 서명 위조 → /login
 *  - access 만료 + refresh 쿠키 없음 → /login
 *  - access 만료 + refresh 쿠키 있음 → 통과(프록시가 첫 API 호출 때 refresh)
 *  - 유효하지만 role!=='admin' → /login
 */
import { jwtVerify } from 'jose';
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

import { COOKIE_ACCESS, COOKIE_REFRESH, getJwtSecret } from './lib/config';

async function isValidAdmin(token: string): Promise<'ok' | 'expired' | 'invalid'> {
  try {
    const { payload } = await jwtVerify(token, getJwtSecret());
    return payload.role === 'admin' ? 'ok' : 'invalid';
  } catch (err) {
    // jose는 만료 시 'ERR_JWT_EXPIRED' code를 던진다 — 서명은 유효하나 만료.
    if (err && typeof err === 'object' && (err as { code?: string }).code === 'ERR_JWT_EXPIRED') {
      return 'expired';
    }
    return 'invalid';
  }
}

export async function middleware(req: NextRequest): Promise<NextResponse> {
  const access = req.cookies.get(COOKIE_ACCESS)?.value;
  const hasRefresh = Boolean(req.cookies.get(COOKIE_REFRESH)?.value);
  const loginUrl = new URL('/login', req.url);

  if (!access) return NextResponse.redirect(loginUrl);

  const state = await isValidAdmin(access);
  if (state === 'ok') return NextResponse.next();
  if (state === 'expired' && hasRefresh) return NextResponse.next();
  return NextResponse.redirect(loginUrl);
}

export const config = {
  // /login, /api/*(세션·프록시 자체가 인증 처리), _next, 파일 확장자 제외 전부 보호
  matcher: ['/((?!login|api|_next/static|_next/image|favicon.ico|.*\\.).*)'],
};
