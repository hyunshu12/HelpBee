/**
 * Hono 앱 구성 + 실제 의존성 와이어링 (backend-design §7 미들웨어 체인).
 * createApp()이 env/DB/Redis/S3/AI 클라이언트를 만들고 라우트 deps 어댑터로 주입한다.
 * 실 인프라 의존이라 통합 검증 대상(pragma) — 라우트/서비스 로직은 단위 검증됨.
 *
 * TODO(§7 SHOULD): pino 로거, CORS allowlist, Redis sliding-window rate-limit 추가.
 */
import { S3Client } from '@aws-sdk/client-s3';
import { db, queries } from '@helpbee/database';
import axios from 'axios';
import { Hono } from 'hono';
import { secureHeaders } from 'hono/secure-headers';
import Redis from 'ioredis';

import { loadEnv } from './config/env';
import { errorHandler } from './middleware/error-handler';
import { requireAuth } from './middleware/auth';
import { requestId } from './middleware/request-id';
import { analysesRoutes, type AnalysesDeps } from './routes/analyses';
import { imagesRoutes, type ImagesDeps } from './routes/images';
import { createAiClient } from './services/ai-client';
import * as quota from './services/quota-service';
import * as s3 from './services/s3-client';

export function createApp() {
  // pragma: no cover - 통합(실 인프라) 대상
  const env = loadEnv();
  const redis = new Redis(env.REDIS_URL);
  const s3client = new S3Client({ region: env.AWS_REGION });
  const http = axios.create({ baseURL: env.AI_BASE_URL });
  const aiClient = createAiClient({
    baseURL: env.AI_BASE_URL,
    hmacSecret: env.AI_INTERNAL_HMAC_SECRET,
    http,
  });
  const bucket = env.S3_IMAGES_BUCKET;

  const analysesDeps: AnalysesDeps = {
    getImageForUser: async (imageId, userId) => {
      const img = await queries.images.getAnalysisImageByIdForUser(db, imageId, userId);
      return img ? { id: img.id, hiveId: img.hiveId, storageUrl: img.storageUrl } : undefined;
    },
    findSuccessByImage: (imageId, userId) =>
      queries.analyses.findSuccessAnalysisByImage(db, imageId, userId),
    getEmailVerifiedAt: async (userId) =>
      (await queries.accounts.getUserById(db, userId))?.emailVerifiedAt ?? null,
    getPlan: async (userId) =>
      ((await queries.accounts.getSubscriptionForUser(db, userId))?.plan as
        | 'free'
        | 'basic'
        | 'pro') ?? 'free',
    reserveQuota: async (userId) => {
      await quota.reserve(redis, userId);
    },
    refundQuota: (userId) => quota.refund(redis, userId),
    presignGet: (objectKey) => s3.presignGet(s3client, bucket, objectKey),
    resolveModelId: async (provider) =>
      (await queries.models.resolveActiveModel(db, provider))?.id,
    analyze: (input) => aiClient.analyze(input),
    storeAnalysis: (input) =>
      queries.analyses.createSingleAnalysis(db, {
        hiveId: input.hiveId,
        imageId: input.imageId,
        modelId: input.modelId,
        // route가 NewAnalysis 필드와 동일 형태로 구성 (런타임 정합)
        analysis: input.analysis as never,
        recommendations: input.recommendations,
      }),
    listForUser: (hiveId, userId, opts) =>
      queries.analyses.listAnalysesByHiveForUser(db, hiveId, userId, opts),
    getByIdForUser: (id, userId) => queries.analyses.getAnalysisByIdForUser(db, id, userId),
    getTrend: (hiveId, userId, from, to) => queries.hives.getHiveTrend(db, hiveId, userId, from, to),
  };

  const imagesDeps: ImagesDeps = {
    objectKeyFor: (userId, ext) => s3.objectKey(userId, ext),
    presignPut: (key, contentType) => s3.presignPut(s3client, bucket, key, contentType),
    headObject: (key) => s3.headObject(s3client, bucket, key),
    getObjectBytes: (key) => s3.getObjectBytes(s3client, bucket, key),
    putObjectBytes: (key, bytes, contentType) =>
      s3.putObjectBytes(s3client, bucket, key, bytes, contentType),
    deleteObject: (key) => s3.deleteObject(s3client, bucket, key),
    validateAndStrip: (bytes) => s3.validateAndStrip(bytes),
    getHiveForUser: async (hiveId, userId) => {
      const hive = await queries.hives.getHiveByIdForUser(db, hiveId, userId);
      return hive ? { id: hive.id } : undefined;
    },
    createImage: (input) => queries.images.createAnalysisImage(db, input as never),
  };

  const app = new Hono();
  app.onError(errorHandler);
  app.use('*', requestId);
  app.use('*', secureHeaders());
  app.get('/health', (c) => c.json({ status: 'ok', timestamp: new Date().toISOString() }));

  // 보호 라우트(/v1/*)는 requireAuth 이후 마운트
  app.use('/v1/*', requireAuth(env.JWT_SECRET));
  app.route('/v1/images', imagesRoutes(imagesDeps));
  app.route('/v1/analyses', analysesRoutes(analysesDeps));

  return app;
}
