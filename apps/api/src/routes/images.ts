/**
 * images 라우트 (backend-design §7, §10, §13 업로드 보안).
 * POST /v1/images/presign: presigned PUT URL + objectKey 발급(5분).
 * POST /v1/images/confirm: 키 소유권 + hive 소유권 → HEAD → 다운로드 →
 *   validateAndStrip(매직넘버·10MB·EXIF strip·bomb) → strip본 재업로드 → 메타 저장.
 *   검증 실패 시 S3 객체 삭제 + 4xx. DI로 S3/DB 분리 → 목 단위 검증.
 */
import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { created, ok } from '../lib/envelope';
import { problem } from '../lib/problem';
import { confirmSchema, presignSchema } from '../schemas/images';

const EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

export type StrippedImage = {
  jpeg: Buffer;
  mime: string;
  width: number;
  height: number;
  byteSize: number;
};

export type ImagesDeps = {
  objectKeyFor(userId: string, ext: string): string;
  presignPut(objectKey: string, contentType: string): Promise<string>;
  headObject(objectKey: string): Promise<unknown>; // 없으면 AppError throw
  getObjectBytes(objectKey: string): Promise<Buffer>;
  putObjectBytes(objectKey: string, bytes: Buffer, contentType: string): Promise<void>;
  deleteObject(objectKey: string): Promise<void>;
  validateAndStrip(bytes: Buffer): Promise<StrippedImage>; // AppError(UNSUPPORTED_MEDIA 등)
  getHiveForUser(hiveId: string, userId: string): Promise<{ id: string } | undefined>;
  createImage(input: {
    hiveId: string;
    uploadedBy: string;
    storageUrl: string;
    mimeType: string;
    width: number;
    height: number;
    byteSize: number;
    capturedAt: Date | null;
  }): Promise<unknown>;
};

export function imagesRoutes(deps: ImagesDeps) {
  const app = new Hono();

  app.post('/presign', zValidator('json', presignSchema), async (c) => {
    const userId = c.get('userId') as string;
    const { contentType } = c.req.valid('json');
    const objectKey = deps.objectKeyFor(userId, EXT[contentType]);
    const uploadUrl = await deps.presignPut(objectKey, contentType);
    return ok(c, { uploadUrl, objectKey, expiresIn: 300 });
  });

  app.post('/confirm', zValidator('json', confirmSchema), async (c) => {
    const userId = c.get('userId') as string;
    const { objectKey, hiveId, capturedAt } = c.req.valid('json');

    // 키 IDOR 차단: objectKey는 반드시 이 사용자 prefix.
    if (!objectKey.startsWith(`images/${userId}/`)) return problem(c, 'NOT_FOUND');

    const hive = await deps.getHiveForUser(hiveId, userId);
    if (!hive) return problem(c, 'NOT_FOUND');

    await deps.headObject(objectKey); // 없으면 AppError(IMAGE_NOT_FOUND_IN_STORAGE) → error-handler

    let stripped: StrippedImage;
    try {
      const bytes = await deps.getObjectBytes(objectKey);
      stripped = await deps.validateAndStrip(bytes);
    } catch (err) {
      await deps.deleteObject(objectKey); // 검증 실패 시 객체 정리
      throw err; // AppError(UNSUPPORTED_MEDIA/IMAGE_TOO_LARGE/IMAGE_INVALID) → error-handler
    }

    await deps.putObjectBytes(objectKey, stripped.jpeg, 'image/jpeg'); // EXIF strip본 재업로드
    const row = await deps.createImage({
      hiveId,
      uploadedBy: userId,
      storageUrl: objectKey,
      mimeType: stripped.mime,
      width: stripped.width,
      height: stripped.height,
      byteSize: stripped.byteSize,
      capturedAt: capturedAt ? new Date(capturedAt) : null,
    });
    return created(c, row);
  });

  return app;
}
