import { sql } from 'drizzle-orm';
import { check, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

import { timestamps } from './_shared';
import { users } from './users';

/**
 * 사용자별 구독 (user_id UNIQUE — 사용자당 1 row).
 * MVP 단계는 plan='free' 기본 + 결제 없이 시작.
 * status: 'active' | 'inactive' | 'cancelled' (CHECK)
 * plan:   'free' | 'basic' | 'pro' (CHECK)
 */
export const subscriptions = pgTable(
  'subscriptions',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    userId: uuid('user_id')
      .notNull()
      .unique()
      .references(() => users.id, { onDelete: 'cascade' }),
    plan: text('plan').notNull().default('free'),
    status: text('status').notNull().default('active'),
    trialEndsAt: timestamp('trial_ends_at', { withTimezone: true }),
    currentPeriodEnd: timestamp('current_period_end', { withTimezone: true }),
    ...timestamps,
  },
  (t) => ({
    planCheck: check('subscriptions_plan_check', sql`${t.plan} IN ('free', 'basic', 'pro')`),
    statusCheck: check(
      'subscriptions_status_check',
      sql`${t.status} IN ('active', 'inactive', 'cancelled')`,
    ),
  }),
);

export type Subscription = typeof subscriptions.$inferSelect;
export type NewSubscription = typeof subscriptions.$inferInsert;

export const SUBSCRIPTION_PLAN_VALUES = ['free', 'basic', 'pro'] as const;
export type SubscriptionPlan = (typeof SUBSCRIPTION_PLAN_VALUES)[number];

export const SUBSCRIPTION_STATUS_VALUES = ['active', 'inactive', 'cancelled'] as const;
export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUS_VALUES)[number];
