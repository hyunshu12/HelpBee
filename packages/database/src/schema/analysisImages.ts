import { sql } from 'drizzle-orm';
import { index, integer, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

import { hives } from './hives';
import { users } from './users';

/**
 * 분석 대상 이미지 메타.
 * - storage_url: S3 (또는 호환 스토리지) URL. 바이너리는 저장 안 함.
 * - uploaded_by: restrict — 업로드한 user를 hard delete하려면 image도 정리해야 함.
 * - captured_at: EXIF에서 추출 (없으면 null). PII/위치정보는 apps/api에서 사전 제거 책임.
 * - hard 보존 (소유자 soft delete와 무관하게 row 유지)
 */
export const analysisImages = pgTable(
  'analysis_images',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    hiveId: uuid('hive_id')
      .notNull()
      .references(() => hives.id, { onDelete: 'cascade' }),
    uploadedBy: uuid('uploaded_by')
      .notNull()
      .references(() => users.id, { onDelete: 'restrict' }),
    storageUrl: text('storage_url').notNull(),
    mimeType: text('mime_type').notNull(),
    width: integer('width'),
    height: integer('height'),
    byteSize: integer('byte_size'),
    checksum: text('checksum'),
    capturedAt: timestamp('captured_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    hiveIdIdx: index('analysis_images_hive_id_idx').on(t.hiveId),
  }),
);

export type AnalysisImage = typeof analysisImages.$inferSelect;
export type NewAnalysisImage = typeof analysisImages.$inferInsert;
