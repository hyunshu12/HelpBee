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
    WEBHOOK_HMAC_SECRET: z.string().min(32).optional(), // 결제 webhook 서명(§11.4). 미설정 시 WEBHOOK_DISABLED.
    SUBSCRIPTION_WEBHOOK_ENABLED: z.coerce.boolean().default(false), // MVP inert 기본
    SENTRY_DSN: z.string().optional(),
    // 이메일 인증 발송(P1-4). console=로그만(로컬 기본) / resend=Resend REST API.
    EMAIL_PROVIDER: z.enum(['console', 'resend']).default('console'),
    // 빈 문자열은 미설정으로 취급(refine에서 resend일 때만 필수).
    RESEND_API_KEY: z
      .string()
      .optional()
      .transform((v) => (v && v.length > 0 ? v : undefined)),
    EMAIL_FROM: z.string().min(1).default('HelpBee <onboarding@resend.dev>'),
    EMAIL_VERIFY_BASE_URL: z.string().min(1).default('http://localhost:3001'),
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
    if (v.EMAIL_PROVIDER === 'resend' && !v.RESEND_API_KEY) {
      ctx.addIssue({
        code: 'custom',
        message: 'RESEND_API_KEY is required when EMAIL_PROVIDER=resend',
        path: ['RESEND_API_KEY'],
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
