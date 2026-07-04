import { sql } from 'drizzle-orm';
import { check, index, pgTable, text, uuid } from 'drizzle-orm/pg-core';

import { timestamps } from './_shared';

/**
 * 문의 접수 (apps/web 문의 폼 → apps/api POST /v1/inquiries).
 *
 * - 익명 접수 — user FK 없음 (비로그인 방문자도 제출).
 * - status: 'new' | 'answered' | 'closed' (CHECK). 운영자가 어드민에서 처리 상태 관리.
 * - locale: 제출 시점 UI 로케일('ko'|'en') 기록용. NULL 허용.
 * - hard 보존 (soft delete 없음 — CS/통계 추적). users/hives 외 deleted_at 금지 정책 준수.
 * - 응답에는 message를 echo하지 않음(라우트에서 id만 반환).
 */
export const inquiries = pgTable(
  'inquiries',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    name: text('name').notNull(),
    email: text('email').notNull(),
    message: text('message').notNull(),
    locale: text('locale'),
    status: text('status').notNull().default('new'),
    ...timestamps,
  },
  (t) => ({
    statusIdx: index('inquiries_status_idx').on(t.status),
    createdAtIdx: index('inquiries_created_at_idx').on(t.createdAt),
    statusCheck: check(
      'inquiries_status_check',
      sql`${t.status} IN ('new', 'answered', 'closed')`,
    ),
  }),
);

export type Inquiry = typeof inquiries.$inferSelect;
export type NewInquiry = typeof inquiries.$inferInsert;

export const INQUIRY_STATUS_VALUES = ['new', 'answered', 'closed'] as const;
export type InquiryStatus = (typeof INQUIRY_STATUS_VALUES)[number];
