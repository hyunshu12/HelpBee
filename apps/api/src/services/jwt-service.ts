/**
 * JWT access 토큰 + refresh 토큰 (backend-design §8.5.2, 1부 확정).
 * - access: HS256, 15분, payload {sub, role, ev, iat, exp, (aud)}. PII(email/name) 미포함.
 * - refresh: opaque 랜덤 32바이트 base64url. 검증의 단일 진실 소스는 DB row.
 * - refresh token_hash = HMAC-SHA256(server pepper) — 결정적(raw→row 조회·재사용 감지 가능).
 *   비밀번호 해싱(argon2, password-service)과 별도 서비스로 분리(§13 MUST, 스왑 불가).
 * - access 시크릿 ≠ refresh pepper (config/env superRefine으로 강제).
 */
import { createHmac, randomBytes } from 'node:crypto';

import jwt from 'jwt-simple';

export const ACCESS_TTL_SEC = 900; // 15분
export const REFRESH_TTL_SEC = 7 * 24 * 60 * 60; // 7일

export type AccessClaims = {
  sub: string;
  role: string;
  ev: boolean; // emailVerified — UX 힌트(권위 소스 아님, §8.8)
  iat: number;
  exp: number;
  aud?: string;
};

export function signAccessToken(
  secret: string,
  opts: {
    userId: string;
    role: string;
    emailVerified: boolean;
    ttlSec?: number;
    audience?: string;
    now?: number;
  },
): string {
  const iat = Math.floor((opts.now ?? Date.now()) / 1000);
  const claims: AccessClaims = {
    sub: opts.userId,
    role: opts.role,
    ev: opts.emailVerified,
    iat,
    exp: iat + (opts.ttlSec ?? ACCESS_TTL_SEC),
    ...(opts.audience ? { aud: opts.audience } : {}),
  };
  return jwt.encode(claims, secret, 'HS256');
}

/** opaque refresh 토큰(32바이트 base64url). 클라에 그대로 전달, DB에는 해시만 저장. */
export function generateRefreshToken(): string {
  return randomBytes(32).toString('base64url');
}

/** refresh 토큰 → DB 저장용 결정적 해시(HMAC-SHA256). pepper는 JWT_SECRET과 다른 값. */
export function hashRefreshToken(pepper: string, token: string): string {
  return createHmac('sha256', pepper).update(token).digest('base64url');
}

export function refreshExpiryDate(now: number = Date.now()): Date {
  return new Date(now + REFRESH_TTL_SEC * 1000);
}
