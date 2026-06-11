/**
 * Admin zod 스키마 (backend-design §12.3). 모두 `.strict()`, 파라미터 바인딩.
 */
import { z } from 'zod';

import { uuid } from './common';

export const pageQuery = z
  .object({
    page: z.coerce.number().int().min(1).default(1),
    pageSize: z.coerce.number().int().min(1).max(100).default(20),
  })
  .strict();

export const adminUserListQuery = z
  .object({
    page: z.coerce.number().int().min(1).default(1),
    pageSize: z.coerce.number().int().min(1).max(100).default(20),
    search: z.string().trim().max(120).optional(),
    role: z.enum(['user', 'admin']).optional(),
    status: z.enum(['active', 'blocked', 'deleted']).optional(),
  })
  .strict();

export const adminUserPatchBody = z
  .object({
    role: z.enum(['user', 'admin']).optional(),
    status: z.enum(['active', 'blocked']).optional(), // deleted는 PATCH 금지(별 경로)
  })
  .strict()
  .refine((b) => b.role !== undefined || b.status !== undefined, {
    message: 'role 또는 status 필수',
  });

export const auditLogQuery = z
  .object({
    cursor: z.coerce.bigint().optional(),
    limit: z.coerce.number().int().min(1).max(100).default(50),
    entity: z.string().max(60).optional(),
    action: z.string().max(60).optional(),
    actorId: uuid.optional(),
    from: z.coerce.date().optional(),
    to: z.coerce.date().optional(),
  })
  .strict();

export const metricsQuery = z
  .object({
    from: z.coerce.date().optional(),
    to: z.coerce.date().optional(),
    granularity: z.enum(['day', 'week']).default('day'),
  })
  .strict();

export const imageIdParam = z.object({ imageId: uuid }).strict();
