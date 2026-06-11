import { z } from 'zod';

const uuid = z
  .string()
  .regex(
    /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/,
    'invalid uuid',
  );

export const presignSchema = z
  .object({
    filename: z.string().min(1).max(255),
    contentType: z.enum(['image/jpeg', 'image/png', 'image/webp']),
  })
  .strict();

export const confirmSchema = z
  .object({
    objectKey: z.string().min(1).max(512),
    hiveId: uuid,
    capturedAt: z.string().optional(), // ISO 8601 (EXIF strip 전 클라가 추출)
  })
  .strict();
