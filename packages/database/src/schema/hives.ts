import { sql } from 'drizzle-orm';
import { index, numeric, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

import { softDelete, timestamps } from './_shared';
import { users } from './users';

/**
 * 사용자별 벌통.
 * - latitude/longitude: WGS84 numeric(9,6)
 * - soft delete 대상 (deleted_at). 소유자 user soft delete 시에도 row 보존, 쿼리에서 마스킹.
 */
export const hives = pgTable(
  'hives',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    note: text('note'),
    latitude: numeric('latitude', { precision: 9, scale: 6 }),
    longitude: numeric('longitude', { precision: 9, scale: 6 }),
    address: text('address'),
    installedAt: timestamp('installed_at', { withTimezone: true }),
    ...timestamps,
    ...softDelete,
  },
  (t) => ({
    userIdIdx: index('hives_user_id_idx').on(t.userId),
  }),
);

export type Hive = typeof hives.$inferSelect;
export type NewHive = typeof hives.$inferInsert;
