/**
 * Production/beta 시드 — admin 1계정만 생성한다 (plans/2026-07-07 PR-7).
 *
 * seeds/dev.ts 와의 차이:
 *   - 고정 비밀번호 없음 — ADMIN_EMAIL/ADMIN_PASSWORD 를 env(SSM Parameter Store)로 주입
 *   - DATABASE_URL fallback 없음 (실수로 로컬을 시드하는 사고 방지 — 명시 필수)
 *   - 데모 데이터(hives/analyses) 없음. ai_models 카탈로그만 함께 보장.
 *
 * 실행 (EC2, /opt/helpbee/.env 로드 후):
 *   ADMIN_EMAIL=... ADMIN_PASSWORD=... pnpm --filter @helpbee/database seed:prod
 *   또는 배포 이미지 안에서:
 *   docker compose run --rm --no-deps \
 *     -e ADMIN_EMAIL=... -e ADMIN_PASSWORD=... \
 *     api ./node_modules/.bin/tsx ../../packages/database/src/seeds/prod.ts
 *
 * idempotent — 이미 존재하는 이메일이면 아무것도 바꾸지 않는다(비밀번호 변경 아님).
 */
import argon2 from 'argon2';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';

import * as schema from '../schema';

const ARGON2_OPTS = {
  type: argon2.argon2id,
  memoryCost: 19456,
  timeCost: 2,
  parallelism: 1,
} as const;

const AI_MODELS = [
  { provider: 'openai' as const, name: 'gpt-4o-mini', version: '2024-07-18' },
  { provider: 'yolo' as const, name: 'helpbee-yolov11s', version: '0.1.0' },
];

async function main(): Promise<void> {
  const url = process.env.DATABASE_URL;
  const email = process.env.ADMIN_EMAIL;
  const password = process.env.ADMIN_PASSWORD;

  if (!url) throw new Error('[seed:prod] DATABASE_URL 필수 (fallback 없음 — 의도적)');
  if (!email || !/^\S+@\S+\.\S+$/.test(email)) {
    throw new Error('[seed:prod] ADMIN_EMAIL 필수 (유효한 이메일)');
  }
  if (!password || password.length < 16) {
    throw new Error('[seed:prod] ADMIN_PASSWORD 필수 (16자 이상 — SSM에서 랜덤 생성 권장)');
  }
  if (password === 'helpbee-dev-2026') {
    throw new Error('[seed:prod] dev 고정 비밀번호 재사용 금지 (git에 공개된 값)');
  }

  console.log(`[seed:prod] connecting to ${url.replace(/:[^@:]+@/, ':***@')}`);
  const sql = postgres(url, { max: 1 });
  const db = drizzle(sql, { schema });

  try {
    // ── admin 계정 (select-then-insert — dev.ts 와 동일한 lower(email) 멱등 패턴) ──
    const existing = await db.select().from(schema.users);
    const already = existing.find((u) => u.email.toLowerCase() === email.toLowerCase());
    if (already) {
      console.log(`[seed:prod] '${email}' 이미 존재 (role=${already.role}) — 변경 없음`);
    } else {
      const passwordHash = await argon2.hash(password, ARGON2_OPTS);
      const [admin] = await db
        .insert(schema.users)
        .values({
          email,
          name: 'HelpBee Admin',
          role: 'admin',
          passwordHash,
          emailVerifiedAt: new Date(),
        })
        .returning();
      if (!admin) throw new Error('[seed:prod] admin insert 실패');
      await db
        .insert(schema.subscriptions)
        .values({ userId: admin.id, plan: 'free' as const })
        .onConflictDoNothing({ target: schema.subscriptions.userId });
      await db.insert(schema.auditLog).values({
        actorId: admin.id,
        action: 'seed.prod',
        entity: 'system',
        metadata: { note: 'admin account seeded' },
      });
      console.log(`[seed:prod] admin '${email}' 생성 완료`);
    }

    // ── ai_models 카탈로그 (분석 라우트의 resolveActiveModel 전제) ──
    await db
      .insert(schema.aiModels)
      .values(AI_MODELS)
      .onConflictDoNothing({
        target: [schema.aiModels.provider, schema.aiModels.name, schema.aiModels.version],
      });
    console.log('[seed:prod] ai_models 카탈로그 확인 완료');

    console.log('[seed:prod] done.');
  } finally {
    await sql.end({ timeout: 5 });
  }
}

main().catch((err) => {
  console.error('[seed:prod] failed', err);
  process.exit(1);
});
