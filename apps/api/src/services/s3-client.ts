/**
 * S3 스토리지 클라이언트 (backend-design §7 업로드, §3.8 SSRF, §13 업로드 보안).
 * - presignPut/presignGet: presigned URL 발급(서버는 바이너리 프록시 X).
 * - validateAndStrip: 매직넘버 sniff(jpeg/png/webp) + 10MB + decompression bomb 가드
 *   (sharp limitInputPixels) + EXIF/메타 strip(rotate 후 재인코딩) → polyglot 무력화.
 * - headObject/deleteObject: confirm/검증실패 정리.
 * 키 패턴: images/{userId}/{yyyy}/{mm}/{uuid}.{ext}.
 */
import { randomUUID } from 'node:crypto';

import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  type S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { fileTypeFromBuffer } from 'file-type';
import sharp from 'sharp';

import { AppError } from '../lib/error-codes';

const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/webp']);
const MAX_BYTES = 10 * 1024 * 1024;
const MAX_PIXELS = 50_000_000; // 50MP — decompression bomb 가드

export function objectKey(
  userId: string,
  ext: string,
  opts: { uuid?: string; now?: Date } = {},
): string {
  const now = opts.now ?? new Date();
  const yyyy = now.getUTCFullYear();
  const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
  const uuid = opts.uuid ?? randomUUID();
  return `images/${userId}/${yyyy}/${mm}/${uuid}.${ext}`;
}

export function presignPut(
  s3: S3Client,
  bucket: string,
  key: string,
  contentType: string,
  ttlSec = 300,
): Promise<string> {
  return getSignedUrl(
    s3,
    new PutObjectCommand({ Bucket: bucket, Key: key, ContentType: contentType }),
    { expiresIn: ttlSec },
  );
}

export function presignGet(s3: S3Client, bucket: string, key: string, ttlSec = 120): Promise<string> {
  return getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: ttlSec });
}

export type ValidatedImage = {
  jpeg: Buffer;
  mime: string;
  width: number;
  height: number;
  byteSize: number;
};

export async function validateAndStrip(bytes: Buffer): Promise<ValidatedImage> {
  if (bytes.length > MAX_BYTES) {
    throw new AppError('IMAGE_TOO_LARGE');
  }
  const ft = await fileTypeFromBuffer(bytes);
  if (!ft || !ALLOWED_MIME.has(ft.mime)) {
    throw new AppError('UNSUPPORTED_MEDIA'); // Content-Type 헤더 불신, 실제 매직넘버 판별
  }
  try {
    const out = await sharp(bytes, { limitInputPixels: MAX_PIXELS })
      .rotate() // EXIF orientation 적용
      .jpeg({ quality: 85 }) // 재인코딩 → 메타데이터/polyglot 제거
      .toBuffer({ resolveWithObject: true });
    return {
      jpeg: out.data,
      mime: 'image/jpeg',
      width: out.info.width,
      height: out.info.height,
      byteSize: out.data.length,
    };
  } catch (err) {
    if (err instanceof AppError) throw err;
    throw new AppError('IMAGE_INVALID');
  }
}

export async function headObject(s3: S3Client, bucket: string, key: string) {
  try {
    return await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
  } catch {
    throw new AppError('IMAGE_NOT_FOUND_IN_STORAGE');
  }
}

export async function deleteObject(s3: S3Client, bucket: string, key: string): Promise<void> {
  await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
}
