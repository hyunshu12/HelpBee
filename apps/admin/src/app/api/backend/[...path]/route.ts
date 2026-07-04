/**
 * ALL /api/backend/[...path] — 서버 프록시. 브라우저는 same-origin만 호출(CORS 없음, 토큰 미노출, §4-2).
 * - access 쿠키를 Authorization: Bearer로 부착, x-request-id 전파
 * - 경로 allowlist(admin/, auth/me)로 방어
 * - 401 + AUTH_TOKEN_EXPIRED & refresh 쿠키 존재 시: /v1/auth/refresh 1회 → 새 쿠키 저장 → 원요청 1회 재시도
 * - refresh 실패 시 401을 그대로 흘림(클라 api.ts가 /login으로)
 */
import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

import { API_URL, COOKIE_ACCESS, COOKIE_REFRESH } from '@/src/lib/config';
import { setSessionCookies } from '@/src/lib/session';

const ALLOWED_PREFIXES = ['admin/', 'auth/me'];

function isAllowed(path: string): boolean {
  return ALLOWED_PREFIXES.some((p) => path === p || path.startsWith(p));
}

interface UpstreamResult {
  status: number;
  headers: Headers;
  text: string;
}

async function callUpstream(
  path: string,
  search: string,
  method: string,
  accessToken: string | undefined,
  bodyText: string | undefined,
  requestId: string | null,
): Promise<UpstreamResult> {
  const headers: Record<string, string> = {};
  if (accessToken) headers.authorization = `Bearer ${accessToken}`;
  if (requestId) headers['x-request-id'] = requestId;
  if (bodyText !== undefined) headers['content-type'] = 'application/json';

  const upstream = await fetch(`${API_URL}/v1/${path}${search}`, {
    method,
    headers,
    body: bodyText,
    cache: 'no-store',
  });
  return { status: upstream.status, headers: upstream.headers, text: await upstream.text() };
}

async function tryRefresh(refreshToken: string): Promise<{ accessToken: string; refreshToken: string } | null> {
  const res = await fetch(`${API_URL}/v1/auth/refresh`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
    cache: 'no-store',
  });
  if (!res.ok) return null;
  const parsed = (await res.json()) as { data: { accessToken: string; refreshToken: string } };
  return { accessToken: parsed.data.accessToken, refreshToken: parsed.data.refreshToken };
}

async function handle(req: Request, ctx: { params: { path?: string[] } }): Promise<NextResponse> {
  const path = (ctx.params.path ?? []).join('/');
  if (!isAllowed(path)) {
    return NextResponse.json({ code: 'NOT_FOUND' }, { status: 404 });
  }

  const url = new URL(req.url);
  const search = url.search;
  const method = req.method;
  const requestId = req.headers.get('x-request-id');
  const bodyText =
    method === 'GET' || method === 'HEAD' || method === 'DELETE' ? undefined : await req.text();

  const jar = cookies();
  const accessToken = jar.get(COOKIE_ACCESS)?.value;
  const refreshToken = jar.get(COOKIE_REFRESH)?.value;

  let result = await callUpstream(path, search, method, accessToken, bodyText, requestId);
  let rotated: { accessToken: string; refreshToken: string } | null = null;

  // access 만료 → refresh 1회 → 원요청 1회 재시도
  if (result.status === 401 && refreshToken) {
    const parsed = safeParse(result.text);
    if (parsed?.code === 'AUTH_TOKEN_EXPIRED' || parsed?.code === 'AUTH_UNAUTHORIZED') {
      rotated = await tryRefresh(refreshToken);
      if (rotated) {
        result = await callUpstream(path, search, method, rotated.accessToken, bodyText, requestId);
      }
    }
  }

  const res = new NextResponse(result.text || null, {
    status: result.status,
    headers: { 'content-type': result.headers.get('content-type') ?? 'application/json' },
  });
  const echoId = result.headers.get('x-request-id');
  if (echoId) res.headers.set('x-request-id', echoId);
  if (rotated) setSessionCookies(res, rotated);
  return res;
}

function safeParse(text: string): { code?: string } | null {
  try {
    return text ? (JSON.parse(text) as { code?: string }) : null;
  } catch {
    return null;
  }
}

export {
  handle as GET,
  handle as POST,
  handle as PATCH,
  handle as PUT,
  handle as DELETE,
};
