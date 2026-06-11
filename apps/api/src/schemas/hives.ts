/**
 * Hives zod 스키마 (backend-design §9.2). hives 컬럼에 1:1, 모두 `.strict()`.
 * - userId는 클라가 보내지 않음 — 항상 c.get('userId')(Mass Assignment 차단, §9.2/§13 MUST).
 * - 반쪽 좌표 금지(create). update는 partial이라 단일 좌표 갱신 허용(§9.2).
 */
import { z } from 'zod';

import { paginationSchema, uuid } from './common';

const latitude = z.number().min(-90).max(90);
const longitude = z.number().min(-180).max(180);
const name = z.string().trim().min(1).max(100); // hives.name NOT NULL
const note = z.string().trim().max(1000);
const address = z.string().trim().max(255);

export const createHiveSchema = z
  .object({
    name,
    note: note.optional(),
    latitude: latitude.optional(),
    longitude: longitude.optional(),
    address: address.optional(),
    installedAt: z.coerce.date().optional(),
  })
  .strict()
  .refine((v) => (v.latitude == null) === (v.longitude == null), {
    message: 'latitude and longitude must be provided together',
    path: ['latitude'],
  });

export const updateHiveSchema = z
  .object({
    name: name.optional(),
    note: note.optional(),
    latitude: latitude.optional(),
    longitude: longitude.optional(),
    address: address.optional(),
    installedAt: z.coerce.date().optional(),
  })
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'at least one field required' });

export const hiveIdParam = z.object({ id: uuid }).strict();
export const listHivesQuery = paginationSchema; // §6.4 (limit 1~100 default 50, offset 0~10000)

export type CreateHiveInput = z.infer<typeof createHiveSchema>;
export type UpdateHiveInput = z.infer<typeof updateHiveSchema>;
