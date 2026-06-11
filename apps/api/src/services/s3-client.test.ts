import {
  DeleteObjectCommand,
  HeadObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { mockClient } from 'aws-sdk-client-mock';
import sharp from 'sharp';
import { afterEach, describe, expect, it } from 'vitest';

import { AppError } from '../lib/error-codes';
import {
  deleteObject,
  headObject,
  objectKey,
  presignGet,
  presignPut,
  validateAndStrip,
} from './s3-client';

const s3mock = mockClient(S3Client);
afterEach(() => s3mock.reset());

function s3() {
  return new S3Client({
    region: 'ap-northeast-2',
    credentials: { accessKeyId: 'AKIATEST', secretAccessKey: 'secret' },
  });
}

async function pngBuf(w = 20, h = 12): Promise<Buffer> {
  return sharp({ create: { width: w, height: h, channels: 3, background: { r: 1, g: 2, b: 3 } } })
    .png()
    .toBuffer();
}

describe('objectKey', () => {
  it('builds images/{userId}/{yyyy}/{mm}/{uuid}.{ext}', () => {
    const key = objectKey('u1', 'jpg', { uuid: 'abc', now: new Date('2026-06-10T00:00:00Z') });
    expect(key).toBe('images/u1/2026/06/abc.jpg');
  });
});

describe('validateAndStrip', () => {
  it('accepts png, returns stripped jpeg with dimensions', async () => {
    const out = await validateAndStrip(await pngBuf(20, 12));
    expect(out.mime).toBe('image/jpeg');
    expect(out.width).toBe(20);
    expect(out.height).toBe(12);
    const meta = await sharp(out.jpeg).metadata();
    expect(meta.format).toBe('jpeg');
    expect(meta.exif).toBeUndefined(); // 메타데이터 제거됨
  });

  it('applies EXIF orientation then strips it', async () => {
    const input = await sharp({
      create: { width: 30, height: 10, channels: 3, background: { r: 9, g: 9, b: 9 } },
    })
      .withMetadata({ orientation: 6 }) // rotate 90
      .jpeg()
      .toBuffer();
    const out = await validateAndStrip(input);
    expect(out.width).toBe(10); // 회전 적용으로 가로/세로 swap
    expect(out.height).toBe(30);
    const meta = await sharp(out.jpeg).metadata();
    expect(meta.orientation === undefined || meta.orientation === 1).toBe(true);
  });

  it('rejects unsupported type (magic-number sniff)', async () => {
    await expect(validateAndStrip(Buffer.from('this is plain text not an image'))).rejects.toMatchObject(
      { code: 'UNSUPPORTED_MEDIA' },
    );
  });

  it('rejects oversized payload (>10MB)', async () => {
    await expect(validateAndStrip(Buffer.alloc(10 * 1024 * 1024 + 1))).rejects.toMatchObject({
      code: 'IMAGE_TOO_LARGE',
    });
  });

  it('rejects corrupt image with valid magic but bad body', async () => {
    const real = await pngBuf(20, 12);
    const truncated = real.subarray(0, 40); // PNG 매직은 유지, 본문 손상
    await expect(validateAndStrip(truncated)).rejects.toBeInstanceOf(AppError);
  });
});

describe('presign (offline URL generation)', () => {
  it('presignPut returns signed URL with key + expiry', async () => {
    const url = await presignPut(s3(), 'helpbee-images-dev', 'images/u1/2026/06/x.jpg', 'image/jpeg', 300);
    expect(url).toMatch(/^https:\/\//);
    expect(url).toContain('images/u1/2026/06/x.jpg');
    expect(url).toContain('X-Amz-Expires=300');
  });

  it('presignGet returns signed URL', async () => {
    const url = await presignGet(s3(), 'helpbee-images-dev', 'images/u1/2026/06/x.jpg', 120);
    expect(url).toContain('X-Amz-Expires=120');
  });
});

describe('headObject / deleteObject', () => {
  it('headObject returns metadata when present', async () => {
    s3mock.on(HeadObjectCommand).resolves({ ContentLength: 123 });
    const head = await headObject(s3(), 'b', 'k');
    expect(head.ContentLength).toBe(123);
  });

  it('headObject throws IMAGE_NOT_FOUND_IN_STORAGE when absent', async () => {
    s3mock.on(HeadObjectCommand).rejects(new Error('NotFound'));
    await expect(headObject(s3(), 'b', 'k')).rejects.toMatchObject({
      code: 'IMAGE_NOT_FOUND_IN_STORAGE',
    });
  });

  it('deleteObject sends DeleteObjectCommand', async () => {
    s3mock.on(DeleteObjectCommand).resolves({});
    await deleteObject(s3(), 'b', 'k');
    expect(s3mock.commandCalls(DeleteObjectCommand).length).toBe(1);
  });
});
