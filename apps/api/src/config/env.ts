/**
 * 환경변수 검증 (backend-design §16, fail-fast).
 * process.env 직접 참조 금지 — 이 모듈의 loadEnv()를 통해서만.
 * 시크릿 강도 강제: JWT_SECRET≥64, REFRESH_TOKEN_PEPPER≥32, AI_INTERNAL_HMAC_SECRET≥32.
 * access-JWT / refresh pepper / 내부 HMAC은 서로 다른 값이어야 함(운영 규약).
 */
import { z } from 'zod';

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().min(1),
  JWT_SECRET: z.string().min(64),
  REFRESH_TOKEN_PEPPER: z.string().min(32),
  AI_BASE_URL: z.string().min(1),
  AI_INTERNAL_HMAC_SECRET: z.string().min(32),
  AWS_REGION: z.string().min(1).default('ap-northeast-2'),
  S3_IMAGES_BUCKET: z.string().min(1),
  PORT: z.coerce.number().int().positive().default(3001),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
});

export type Env = z.infer<typeof envSchema>;

export function loadEnv(source: Record<string, unknown> = process.env): Env {
  const parsed = envSchema.safeParse(source);
  if (!parsed.success) {
    const fields = Object.keys(parsed.error.flatten().fieldErrors);
    throw new Error(`[config] invalid environment: ${fields.join(', ')}`);
  }
  return parsed.data;
}
