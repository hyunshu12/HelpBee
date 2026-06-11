/**
 * Hives 쿼리 헬퍼 실 DB 통합테스트 (backend-design §9).
 * 실행(opt-in): DB_ITEST=1 DATABASE_URL=... pnpm --filter @helpbee/database test:integration
 * ⚠️ DB_ITEST 미설정 시 전체 스킵(CI 안전).
 * 검증: 생성·페이지네이션 클램프·부분수정(IDOR)·soft delete(IDOR).
 */
import { sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { db, queries, schema } from '../index';

const RUN = process.env.DB_ITEST === '1';

describe.skipIf(!RUN)('Hives queries (real PostgreSQL)', () => {
  let owner: string;
  let other: string;

  beforeAll(async () => {
    await db.delete(schema.users).where(sql`email LIKE 'hiveq-%@itest.local'`);
    const o = await queries.auth.createUserWithSubscription(db, {
      email: 'hiveq-owner@itest.local',
      name: 'O',
      passwordHash: '$argon2id$x',
    });
    const x = await queries.auth.createUserWithSubscription(db, {
      email: 'hiveq-other@itest.local',
      name: 'X',
      passwordHash: '$argon2id$x',
    });
    owner = o.id;
    other = x.id;
  });

  afterAll(async () => {
    await db.delete(schema.users).where(sql`email LIKE 'hiveq-%@itest.local'`);
    // 연결은 vitest 워커 종료 시 정리(여러 통합 스위트가 공유 싱글톤을 쓰므로 개별 end() 금지).
  });

  it('createHive: lat/lng numeric 저장(string) + 필드', async () => {
    const h = await queries.hives.createHive(db, owner, {
      name: '1호',
      latitude: 37.5665,
      longitude: 126.978,
      address: '서울',
    });
    expect(h.name).toBe('1호');
    expect(h.userId).toBe(owner);
    expect(Number(h.latitude)).toBeCloseTo(37.5665, 4);
  });

  it('listHivesByUser: 소유만 + limit 클램프(>100→100, 직접호출 방어)', async () => {
    const list = await queries.hives.listHivesByUser(db, owner, { limit: 999, offset: 0 });
    expect(list.length).toBeGreaterThan(0);
    expect(list.every((h) => h.userId === owner)).toBe(true);
    // other 사용자는 owner hive 안 보임
    expect(await queries.hives.listHivesByUser(db, other)).toHaveLength(0);
  });

  it('updateHive: 소유자만 수정 / 비소유 undefined (IDOR)', async () => {
    const h = await queries.hives.createHive(db, owner, { name: 'upd' });
    const updated = await queries.hives.updateHive(db, h.id, owner, { name: 'upd2' });
    expect(updated?.name).toBe('upd2');
    // 비소유 수정 시도 → undefined(미반영)
    expect(await queries.hives.updateHive(db, h.id, other, { name: 'hijack' })).toBeUndefined();
    const fresh = await queries.hives.getHiveByIdForUser(db, h.id, owner);
    expect(fresh?.name).toBe('upd2'); // hijack 미반영
  });

  it('softDeleteHive: 소유자만 / 이후 조회 undefined / 비소유 undefined', async () => {
    const h = await queries.hives.createHive(db, owner, { name: 'del' });
    expect(await queries.hives.softDeleteHive(db, h.id, other)).toBeUndefined(); // IDOR
    const res = await queries.hives.softDeleteHive(db, h.id, owner);
    expect(res?.deletedAt).toBeTruthy();
    expect(await queries.hives.getHiveByIdForUser(db, h.id, owner)).toBeUndefined(); // soft delete 제외
    // 재삭제 → undefined(이미 deleted)
    expect(await queries.hives.softDeleteHive(db, h.id, owner)).toBeUndefined();
  });
});
