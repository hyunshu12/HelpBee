import { Hono } from 'hono';
import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../lib/error-codes';
import { errorHandler } from '../middleware/error-handler';
import { imagesRoutes, type ImagesDeps } from './images';

const HIVE = '11111111-1111-1111-1111-111111111111';
const KEY = 'images/u1/2026/06/abc.jpg';

function baseDeps(over: Partial<ImagesDeps> = {}): ImagesDeps {
  return {
    objectKeyFor: (userId, ext) => `images/${userId}/2026/06/abc.${ext}`,
    presignPut: async (k) => `https://s3/${k}?X-Amz-Expires=300`,
    headObject: async () => ({}),
    getObjectBytes: async () => Buffer.from('fakebytes'),
    putObjectBytes: async () => {},
    deleteObject: async () => {},
    validateAndStrip: async () => ({
      jpeg: Buffer.from('jpeg'),
      mime: 'image/jpeg',
      width: 800,
      height: 600,
      byteSize: 4,
    }),
    getHiveForUser: async () => ({ id: HIVE }),
    createImage: async (input) => ({ id: 'img1', ...input }),
    ...over,
  };
}

function makeApp(deps: ImagesDeps) {
  const app = new Hono();
  app.onError(errorHandler);
  app.use('*', async (c, next) => {
    c.set('userId', 'u1');
    c.set('requestId', 'req-1');
    await next();
  });
  app.route('/v1/images', imagesRoutes(deps));
  return app;
}

function postJson(app: Hono, path: string, body: unknown) {
  return app.request(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('POST /v1/images/presign', () => {
  it('returns uploadUrl + objectKey under user prefix', async () => {
    const res = await postJson(makeApp(baseDeps()), '/v1/images/presign', {
      filename: 'bee.jpg',
      contentType: 'image/jpeg',
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.objectKey).toContain('images/u1/');
    expect(body.data.uploadUrl).toMatch(/^https:\/\//);
    expect(body.data.expiresIn).toBe(300);
  });

  it('rejects disallowed contentType', async () => {
    const res = await postJson(makeApp(baseDeps()), '/v1/images/presign', {
      filename: 'x.gif',
      contentType: 'image/gif',
    });
    expect(res.status).toBe(400);
  });
});

describe('POST /v1/images/confirm', () => {
  it('validates+strips then stores → 201, re-uploads stripped', async () => {
    const putObjectBytes = vi.fn(async () => {});
    const res = await postJson(makeApp(baseDeps({ putObjectBytes })), '/v1/images/confirm', {
      objectKey: KEY,
      hiveId: HIVE,
    });
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.data.storageUrl).toBe(KEY);
    expect(body.data.mimeType).toBe('image/jpeg');
    expect(putObjectBytes).toHaveBeenCalledOnce(); // strip본 재업로드
  });

  it('404 when objectKey not under user prefix (key IDOR)', async () => {
    const res = await postJson(makeApp(baseDeps()), '/v1/images/confirm', {
      objectKey: 'images/other-user/2026/06/x.jpg',
      hiveId: HIVE,
    });
    expect(res.status).toBe(404);
  });

  it('404 when hive not owned', async () => {
    const res = await postJson(
      makeApp(baseDeps({ getHiveForUser: async () => undefined })),
      '/v1/images/confirm',
      { objectKey: KEY, hiveId: HIVE },
    );
    expect(res.status).toBe(404);
  });

  it('404 IMAGE_NOT_FOUND_IN_STORAGE when head fails', async () => {
    const res = await postJson(
      makeApp(
        baseDeps({
          headObject: async () => {
            throw new AppError('IMAGE_NOT_FOUND_IN_STORAGE');
          },
        }),
      ),
      '/v1/images/confirm',
      { objectKey: KEY, hiveId: HIVE },
    );
    expect(res.status).toBe(404);
    expect((await res.json()).code).toBe('IMAGE_NOT_FOUND_IN_STORAGE');
  });

  it('deletes object + 415 when validation fails', async () => {
    const deleteObject = vi.fn(async () => {});
    const res = await postJson(
      makeApp(
        baseDeps({
          deleteObject,
          validateAndStrip: async () => {
            throw new AppError('UNSUPPORTED_MEDIA');
          },
        }),
      ),
      '/v1/images/confirm',
      { objectKey: KEY, hiveId: HIVE },
    );
    expect(res.status).toBe(415);
    expect(deleteObject).toHaveBeenCalledOnce();
  });
});
