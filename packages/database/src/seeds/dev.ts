/**
 * ⚠️ DEV ONLY — 이 스크립트는 development 환경 전용이다.
 *
 * 모든 dev 계정의 비밀번호는 'helpbee-dev-2026' 으로 고정되어 있다.
 * production seed는 별도 (seeds/prod.ts) + Secrets Manager 주입을 사용한다.
 *
 * 실행: pnpm --filter @helpbee/database seed:dev
 *
 * idempotent — 재실행 시 ON CONFLICT DO NOTHING (UNIQUE 제약 활용).
 */
import argon2 from 'argon2';
import { eq } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';

import * as schema from '../schema';

const DEFAULT_URL = 'postgresql://helpbee_user:helpbee_password@localhost:5432/helpbee';
const DEV_PASSWORD = 'helpbee-dev-2026';

const ARGON2_OPTS = {
  type: argon2.argon2id,
  memoryCost: 19456,
  timeCost: 2,
  parallelism: 1,
} as const;

type SeedUser = {
  email: string;
  name: string;
  role: 'user' | 'admin';
};

const SEED_USERS: SeedUser[] = [
  { email: 'admin@helpbee.local', name: 'HelpBee Admin', role: 'admin' },
  { email: 'beekeeper1@helpbee.local', name: '김양봉', role: 'user' },
  { email: 'beekeeper2@helpbee.local', name: '이꿀벌', role: 'user' },
];

const SEED_AI_MODELS = [
  {
    provider: 'openai' as const,
    name: 'gpt-4o-mini',
    version: '2024-07-18',
  },
  {
    provider: 'yolo' as const,
    name: 'helpbee-yolov8s',
    version: '0.1.0',
  },
];

async function main(): Promise<void> {
  const url = process.env.DATABASE_URL ?? DEFAULT_URL;
  console.log(`[seed:dev] connecting to ${url.replace(/:[^@:]+@/, ':***@')}`);

  const sql = postgres(url, { max: 1 });
  const db = drizzle(sql, { schema });

  try {
    const passwordHash = await argon2.hash(DEV_PASSWORD, ARGON2_OPTS);

    // ─────────────── users ───────────────
    // users.email은 컬럼 UNIQUE() 대신 lower(email) partial index로 관리되므로
    // drizzle의 `onConflictDoNothing({ target: column })` 사용 불가 (PG에서 인식 못 함).
    // → select-then-insert 패턴으로 멱등성 확보.
    const existingUsers = await db.select().from(schema.users);
    const existingEmails = new Set(existingUsers.map((u) => u.email.toLowerCase()));
    const toInsert = SEED_USERS.filter((u) => !existingEmails.has(u.email.toLowerCase())).map(
      (u) => ({
        email: u.email,
        name: u.name,
        role: u.role,
        passwordHash,
        emailVerifiedAt: new Date(),
      }),
    );
    const userRows = toInsert.length
      ? await db.insert(schema.users).values(toInsert).returning()
      : [];
    console.log(
      `[seed:dev] users inserted: ${userRows.length} (existing ${existingUsers.length} skipped)`,
    );

    // id 확보 위해 전체 조회 (방금 insert + 기존)
    const allUsers = await db.select().from(schema.users);
    const adminUser = allUsers.find((u) => u.email === 'admin@helpbee.local');
    const bk1 = allUsers.find((u) => u.email === 'beekeeper1@helpbee.local');
    const bk2 = allUsers.find((u) => u.email === 'beekeeper2@helpbee.local');
    if (!adminUser || !bk1 || !bk2) {
      throw new Error('[seed:dev] seed users not found after insert');
    }

    // ─────────────── ai_models ───────────────
    await db
      .insert(schema.aiModels)
      .values(SEED_AI_MODELS)
      .onConflictDoNothing({
        target: [schema.aiModels.provider, schema.aiModels.name, schema.aiModels.version],
      });
    const allModels = await db.select().from(schema.aiModels);
    const openaiModel = allModels.find((m) => m.provider === 'openai');
    const yoloModel = allModels.find((m) => m.provider === 'yolo');
    if (!openaiModel || !yoloModel) {
      throw new Error('[seed:dev] seed ai_models not found');
    }
    console.log(`[seed:dev] ai_models present: openai=${openaiModel.version}, yolo=${yoloModel.version}`);

    // ─────────────── subscriptions ───────────────
    await db
      .insert(schema.subscriptions)
      .values(allUsers.map((u) => ({ userId: u.id, plan: 'free' as const })))
      .onConflictDoNothing({ target: schema.subscriptions.userId });

    // ─────────────── hives ───────────────
    // 멱등성 확보: 같은 (userId, name) 조합이 이미 있으면 skip. drizzle에서 partial unique가
    // 없으므로 select 후 분기.
    const hiveSeeds = [
      { userId: bk1.id, name: '양봉장 1호', address: '경기도 양평군', latitude: 37.4912, longitude: 127.4876 },
      { userId: bk1.id, name: '양봉장 2호', address: '경기도 양평군', latitude: 37.4928, longitude: 127.4855 },
      { userId: bk1.id, name: '양봉장 3호', address: '경기도 양평군', latitude: 37.4945, longitude: 127.4901 },
      { userId: bk2.id, name: '강원농장 A', address: '강원도 홍천군', latitude: 37.6932, longitude: 127.8881 },
      { userId: bk2.id, name: '강원농장 B', address: '강원도 홍천군', latitude: 37.6945, longitude: 127.8902 },
    ];
    const existingHives = await db.select().from(schema.hives);
    const existingKey = new Set(existingHives.map((h) => `${h.userId}:${h.name}`));
    const newHives = hiveSeeds.filter((h) => !existingKey.has(`${h.userId}:${h.name}`));
    if (newHives.length > 0) {
      await db.insert(schema.hives).values(
        newHives.map((h) => ({
          ...h,
          installedAt: new Date('2026-03-01T00:00:00Z'),
          latitude: String(h.latitude),
          longitude: String(h.longitude),
        })),
      );
    }
    const allHives = await db.select().from(schema.hives);
    console.log(`[seed:dev] hives present: ${allHives.length}`);

    // ─────────────── analysis_images + analyses (dual-engine) ───────────────
    // 같은 image_id에 (openai, yolo) 두 row를 5세트 — UNIQUE(image_id, model_id) 검증용.
    // 멱등성: analysis_images 가 0개일 때만 시드 세트 생성.
    // (DB에 이미 이미지가 1개라도 있으면 재시드 안 함 — 운영 DB 보호)
    const existingImages = await db.select().from(schema.analysisImages);
    const imagesCount = existingImages.length;
    if (imagesCount === 0 && allHives.length > 0) {
      const dualSets = 5;
      const targetHive = allHives[0]!;
      for (let i = 0; i < dualSets; i++) {
        const [img] = await db
          .insert(schema.analysisImages)
          .values({
            hiveId: targetHive.id,
            uploadedBy: targetHive.userId,
            storageUrl: `s3://helpbee-images-dev/seed/${targetHive.id}/dual-${i}.jpg`,
            mimeType: 'image/jpeg',
            width: 1920,
            height: 1080,
            byteSize: 350_000,
            checksum: `seed-checksum-${i}`,
            capturedAt: new Date(Date.now() - (dualSets - i) * 24 * 60 * 60 * 1000),
          })
          .returning();
        if (!img) continue;

        const baseRisk = 25 + i * 12; // 25, 37, 49, 61, 73
        const overallHealth =
          baseRisk < 35 ? 'healthy' : baseRisk < 65 ? 'warning' : 'critical';
        const analyzedAt = new Date();

        const [openaiAn] = await db
          .insert(schema.analyses)
          .values({
            hiveId: targetHive.id,
            imageId: img.id,
            modelId: openaiModel.id,
            status: 'success',
            varroaInfectionRisk: baseRisk,
            estimatedVarroaCount: Math.round(baseRisk / 5),
            overallHealth,
            rawResponse: { engine: 'openai', mock: true },
            latencyMs: 3200,
            analyzedAt,
          })
          .returning();
        const [yoloAn] = await db
          .insert(schema.analyses)
          .values({
            hiveId: targetHive.id,
            imageId: img.id,
            modelId: yoloModel.id,
            status: 'success',
            varroaInfectionRisk: baseRisk + 3, // 모델별 미세 차이
            estimatedVarroaCount: Math.round((baseRisk + 3) / 5),
            overallHealth,
            rawResponse: { engine: 'yolo', mock: true, boxes: [] },
            latencyMs: 1400,
            analyzedAt,
          })
          .returning();

        if (openaiAn) {
          await db.insert(schema.recommendations).values([
            {
              analysisId: openaiAn.id,
              order: 0,
              content: '벌통 내부 통풍 상태를 점검하세요.',
              severity: baseRisk >= 70 ? 'danger' : 'info',
            },
          ]);
        }
        if (yoloAn) {
          await db.insert(schema.recommendations).values([
            {
              analysisId: yoloAn.id,
              order: 0,
              content: '응애 의심 영역이 감지되었습니다. 7일 내 재촬영 권장.',
              severity: baseRisk >= 70 ? 'danger' : 'warn',
            },
          ]);
        }
      }
      console.log(`[seed:dev] created ${dualSets} dual-engine analysis sets`);
    } else {
      console.log('[seed:dev] analysis_images already present — skipping dual analyses');
    }

    // ─────────────── audit_log ───────────────
    // 멱등성: 시드 마커 row 1개만 유지 (audit_log는 hard 보존이지만 시드 자체는 멱등 강제)
    const existingSeedAudit = await db
      .select()
      .from(schema.auditLog)
      .where(eq(schema.auditLog.action, 'seed.dev'))
      .limit(1);
    if (existingSeedAudit.length === 0) {
      await db.insert(schema.auditLog).values({
        actorId: adminUser.id,
        action: 'seed.dev',
        entity: 'system',
        metadata: { note: 'seed:dev executed' },
      });
    }

    console.log('[seed:dev] done.');
  } finally {
    await sql.end({ timeout: 5 });
  }
}

main().catch((err) => {
  console.error('[seed:dev] failed', err);
  process.exit(1);
});
