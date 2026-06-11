/**
 * 환경변수 검증 (backend-design §16, fail-fast).
 * process.env 직접 참조 금지 — 이 모듈의 loadEnv()를 통해서만.
 * 시크릿 강도 강제: JWT_SECRET≥64, REFRESH_TOKEN_PEPPER≥32, AI_INTERNAL_HMAC_SECRET≥32.
 * access-JWT / refresh pepper / 내부 HMAC은 서로 다른 값이어야 함(§16 superRefine).
 * 플레이스홀더 시크릿(your_..._here/changeme/placeholder)은 부팅 거부(§13 MUST).
 */
import { z } from 'zod';

const csv = z
  .string()
  .default('')
  .transform((s) =>
    s
      .split(',')
      .map((v) => v.trim())
      .filter(Boolean),
  );

const envSchema = z
  .object({
    DATABASE_URL: z.string().min(1),
    REDIS_URL: z.string().min(1),
    JWT_SECRET: z.string().min(64),
    REFRESH_TOKEN_PEPPER: z.string().min(32),
    JWT_ACCESS_TTL_SEC: z.coerce.number().int().positive().default(900), // 15m
    JWT_REFRESH_TTL_SEC: z.coerce.number().int().positive().default(604800), // 7d
    JWT_ADMIN_AUDIENCE: z.string().min(1).default('helpbee-admin'),
    CORS_ALLOWLIST: csv, // 콤마구분 origin allowlist (와일드카드 금지)
    AUTH_LOGIN_MAX_FAILS: z.coerce.number().int().positive().default(10),
    AUTH_LOCKOUT_WINDOW_SEC: z.coerce.number().int().positive().default(900),
    AI_BASE_URL: z.string().min(1),
    AI_INTERNAL_HMAC_SECRET: z.string().min(32),
    AWS_REGION: z.string().min(1).default('ap-northeast-2'),
    S3_IMAGES_BUCKET: z.string().min(1),
    PORT: z.coerce.number().int().positive().default(3001),
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  })
  .superRefine((v, ctx) => {
    if (/your_.*_here|changeme|placeholder/i.test(v.JWT_SECRET)) {
      ctx.addIssue({ code: 'custom', message: 'placeholder JWT_SECRET', path: ['JWT_SECRET'] });
    }
    if (v.JWT_SECRET === v.REFRESH_TOKEN_PEPPER) {
      ctx.addIssue({
        code: 'custom',
        message: 'JWT_SECRET must differ from REFRESH_TOKEN_PEPPER',
        path: ['REFRESH_TOKEN_PEPPER'],
      });
    }
    if (v.AI_INTERNAL_HMAC_SECRET === v.JWT_SECRET) {
      ctx.addIssue({
        code: 'custom',
        message: 'AI_INTERNAL_HMAC_SECRET must differ from JWT_SECRET',
        path: ['AI_INTERNAL_HMAC_SECRET'],
      });
    }
  });

export type Env = z.infer<typeof envSchema>;

export function loadEnv(source: Record<string, unknown> = process.env): Env {
  const parsed = envSchema.safeParse(source);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `${i.path.join('.') || '(root)'}: ${i.message}`)
      .join('; ');
    throw new Error(`[config] invalid environment: ${issues}`);
  }
  return parsed.data;
}
