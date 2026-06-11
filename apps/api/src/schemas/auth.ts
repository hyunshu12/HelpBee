/**
 * Auth zod 스키마 + PublicUser 투영 (backend-design §8.2).
 * 모두 `.strict()` (모르는 키 400 — Mass Assignment 차단, §13 MUST).
 * 이메일은 normalizeEmail로 정규화 후 검증 (DB lower(email) UNIQUE와 정합).
 * zod v4 .email() API 변동 회피 — 정규식 refine.
 */
import { z } from 'zod';

import { normalizeEmail } from './common';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const emailField = z
  .string()
  .min(3)
  .max(254)
  .transform(normalizeEmail)
  .refine((v) => EMAIL_RE.test(v), 'invalid email');

const passwordField = z.string().min(10).max(128); // OWASP 최소 10, 상한 128(argon2 입력 폭주 방지)
const nameField = z.string().trim().min(1).max(60);
const refreshField = z.string().min(1).max(512);

export const signupSchema = z
  .object({ email: emailField, password: passwordField, name: nameField })
  .strict();

// login password는 길이만(min 1) — signup 정책 변경 시 기존 계정 잠김 방지.
export const loginSchema = z
  .object({ email: emailField, password: z.string().min(1).max(128) })
  .strict();

export const refreshSchema = z.object({ refreshToken: refreshField }).strict();
export const logoutSchema = z.object({ refreshToken: refreshField }).strict();

export type SignupInput = z.infer<typeof signupSchema>;
export type LoginInput = z.infer<typeof loginSchema>;

/** users row → 외부 노출 투영. password_hash 절대 미포함, email_verified_at은 boolean으로 파생. */
export type PublicUser = {
  id: string;
  email: string;
  name: string;
  role: 'user' | 'admin';
  emailVerified: boolean;
  createdAt: string;
};

export function toPublicUser(u: {
  id: string;
  email: string;
  name: string;
  role: string;
  emailVerifiedAt: Date | null;
  createdAt: Date;
}): PublicUser {
  return {
    id: u.id,
    email: u.email,
    name: u.name,
    role: u.role === 'admin' ? 'admin' : 'user',
    emailVerified: u.emailVerifiedAt != null,
    createdAt: u.createdAt.toISOString(),
  };
}
