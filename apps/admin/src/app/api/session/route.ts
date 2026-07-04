/**
 * POST /api/session  — 로그인. 서버에서 apps/api /v1/auth/login 호출. role!=='admin'이면 403(쿠키 미설정).
 * DELETE /api/session — 로그아웃. 쿠키 제거.
 * 토큰은 절대 응답 body에 담지 않는다 — httpOnly 쿠키로만.
 */
import { NextResponse } from 'next/server';

import { API_URL } from '@/src/lib/config';
import { clearSessionCookies, setSessionCookies } from '@/src/lib/session';
import type { PublicUser } from '@/src/lib/types';

interface LoginResult {
  user: PublicUser;
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export async function POST(req: Request): Promise<NextResponse> {
  let body: { email?: unknown; password?: unknown };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ code: 'VALIDATION_FAILED' }, { status: 400 });
  }
  const { email, password } = body;
  if (typeof email !== 'string' || typeof password !== 'string') {
    return NextResponse.json({ code: 'VALIDATION_FAILED' }, { status: 400 });
  }

  const upstream = await fetch(`${API_URL}/v1/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
    cache: 'no-store',
  });

  const text = await upstream.text();
  const parsed: unknown = text ? JSON.parse(text) : null;

  if (!upstream.ok) {
    const problem = (parsed ?? {}) as { code?: string };
    const res = NextResponse.json({ code: problem.code ?? 'INTERNAL' }, { status: upstream.status });
    const retryAfter = upstream.headers.get('retry-after');
    if (retryAfter) res.headers.set('retry-after', retryAfter);
    return res;
  }

  const data = (parsed as { data: LoginResult }).data;
  if (data.user.role !== 'admin') {
    // 일반 사용자 로그인은 성공해도 admin 콘솔 진입 불가 — 쿠키를 설정하지 않는다.
    return NextResponse.json({ code: 'FORBIDDEN_ROLE' }, { status: 403 });
  }

  const res = NextResponse.json({ user: data.user });
  setSessionCookies(res, { accessToken: data.accessToken, refreshToken: data.refreshToken });
  return res;
}

export async function DELETE(): Promise<NextResponse> {
  const res = NextResponse.json({ ok: true });
  clearSessionCookies(res);
  return res;
}
