/**
 * 클라이언트 단일 API 진입점. 모든 호출은 same-origin `/api/backend/...` 프록시 경유(§4).
 * - {data, meta} 봉투를 벗겨 data만 반환
 * - problem+json → ApiError(code,status,message)
 * - 401 → /login 리다이렉트 (프록시가 refresh 실패 시에만 401을 흘림)
 * 컴포넌트에서 직접 fetch() 금지 — 항상 이 헬퍼를 통한다.
 */
import { ApiError, messageForCode } from './errors';
import type { Envelope } from './types';

export interface ApiFetchOptions {
  method?: string;
  query?: Record<string, string | number | undefined>;
  body?: unknown;
  signal?: AbortSignal;
}

function buildPath(path: string, query?: ApiFetchOptions['query']): string {
  const clean = path.replace(/^\/+/, '');
  const url = new URL(`/api/backend/${clean}`, window.location.origin);
  if (query) {
    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined && v !== '') url.searchParams.set(k, String(v));
    }
  }
  return url.pathname + url.search;
}

export async function apiFetch<T>(path: string, opts: ApiFetchOptions = {}): Promise<T> {
  const res = await fetch(buildPath(path, opts.query), {
    method: opts.method ?? 'GET',
    headers: opts.body !== undefined ? { 'content-type': 'application/json' } : undefined,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    signal: opts.signal,
  });

  if (res.status === 401) {
    if (typeof window !== 'undefined') window.location.href = '/login';
    throw new ApiError('AUTH_UNAUTHORIZED', 401, messageForCode('AUTH_UNAUTHORIZED'));
  }

  const text = await res.text();
  const parsed: unknown = text ? JSON.parse(text) : null;

  if (!res.ok) {
    const problem = (parsed ?? {}) as { code?: string };
    const code = problem.code ?? 'INTERNAL';
    throw new ApiError(code, res.status, messageForCode(code));
  }

  return (parsed as Envelope<T>).data;
}

/** list 응답: data + meta.pagination.total 을 함께 반환(서버사이드 페이지네이션용). */
export async function apiFetchList<T>(
  path: string,
  opts: ApiFetchOptions = {},
): Promise<{ items: T[]; total: number }> {
  const res = await fetch(buildPath(path, opts.query), {
    method: opts.method ?? 'GET',
    signal: opts.signal,
  });

  if (res.status === 401) {
    if (typeof window !== 'undefined') window.location.href = '/login';
    throw new ApiError('AUTH_UNAUTHORIZED', 401, messageForCode('AUTH_UNAUTHORIZED'));
  }

  const text = await res.text();
  const parsed: unknown = text ? JSON.parse(text) : null;

  if (!res.ok) {
    const problem = (parsed ?? {}) as { code?: string };
    const code = problem.code ?? 'INTERNAL';
    throw new ApiError(code, res.status, messageForCode(code));
  }

  const env = parsed as Envelope<T[]>;
  return { items: env.data, total: env.meta.pagination?.total ?? env.data.length };
}
