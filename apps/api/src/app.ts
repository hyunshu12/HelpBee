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
import { getClientIp } from './lib/client-ip';
import { AppError } from './lib/error-codes';
import { isSessionRevoked, bumpSessionsValidAfter } from './lib/sessions';
import { errorHandler } from './middleware/error-handler';
import { requireAuth, requireAdmin } from './middleware/auth';
import { corsMiddleware } from './middleware/cors';
import { loggerMiddleware } from './middleware/logger';
import { rateLimit } from './middleware/rate-limit';
import { requestId } from './middleware/request-id';
import { webhookSignatureGuard } from './middleware/webhook-signature';
import { adminRoutes, type AdminDeps } from './routes/admin';
import { analysesRoutes, type AnalysesDeps } from './routes/analyses';
import { authRoutes, type AuthDeps } from './routes/auth';
import { hivesRoutes, type HivesDeps } from './routes/hives';
import { imagesRoutes, type ImagesDeps } from './routes/images';
import { inquiriesRoutes, type InquiriesDeps } from './routes/inquiries';
import { subscriptionsRoutes, type SubscriptionsDeps } from './routes/subscriptions';
import * as accountProtection from './services/account-protection';
import { createAiClient } from './services/ai-client';
import {
  generateRefreshToken,
  hashRefreshToken,
  signAccessToken,
} from './services/jwt-service';
import { getDummyHash, hashPassword, verifyPassword } from './services/password-service';
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
    getRecommendations: async (analysisId) =>
      (await queries.analyses.listRecommendationsByAnalysisIds(db, [analysisId])).get(analysisId) ??
      [],
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

  const authDeps: AuthDeps = {
    createUser: (input) => queries.auth.createUserWithSubscription(db, input),
    getUserByEmail: (email) => queries.auth.getUserByEmailForAuth(db, email),
    getActiveUserById: (userId) => queries.auth.getActiveUserById(db, userId),
    getSubscription: async (userId) => {
      const sub = await queries.accounts.getSubscriptionForUser(db, userId);
      return sub ? { plan: sub.plan, status: sub.status } : undefined;
    },
    getRefreshByHash: (hash) => queries.auth.getRefreshTokenByHash(db, hash),
    createRefresh: (input) => queries.auth.createRefreshToken(db, input),
    revokeRefreshById: (id) => queries.auth.revokeRefreshTokenById(db, id),
    revokeAllRefresh: (userId) => queries.auth.revokeAllRefreshTokensForUser(db, userId),
    hashPassword,
    verifyPassword,
    getDummyHash,
    signAccess: ({ userId, role, emailVerified }) =>
      signAccessToken(env.JWT_SECRET, {
        userId,
        role,
        emailVerified,
        ttlSec: env.JWT_ACCESS_TTL_SEC,
        // admin 토큰은 별도 audience로 스코프(§17-4) — 일반 사용자 토큰으로 admin 접근 불가.
        audience: role === 'admin' ? env.JWT_ADMIN_AUDIENCE : undefined,
      }),
    generateRefresh: generateRefreshToken,
    hashRefresh: (token) => hashRefreshToken(env.REFRESH_TOKEN_PEPPER, token),
    refreshExpiry: () => new Date(Date.now() + env.JWT_REFRESH_TTL_SEC * 1000),
    assertNotLocked: ({ email, ip }) =>
      accountProtection.assertNotLocked(redis, { email, ip, maxFails: env.AUTH_LOGIN_MAX_FAILS }),
    recordLoginFailure: ({ email, ip }) =>
      accountProtection
        .recordFailure(redis, { email, ip, windowSec: env.AUTH_LOCKOUT_WINDOW_SEC })
        .then(() => undefined),
    clearLoginFailures: ({ email, ip }) => accountProtection.clearFailures(redis, { email, ip }),
    bumpSessions: (userId) => bumpSessionsValidAfter(redis, userId),
    audit: (entry) => queries.auditLog.appendAuditLog(db, entry),
    now: () => Date.now(),
  };

  const hivesCacheKey = (userId: string) => `cache:hives:${userId}`;
  const hivesDeps: HivesDeps = {
    list: (userId, opts) => queries.hives.listHivesByUser(db, userId, opts),
    create: (userId, input) => queries.hives.createHive(db, userId, input),
    getById: (hiveId, userId) => queries.hives.getHiveByIdForUser(db, hiveId, userId),
    update: (hiveId, userId, patch) => queries.hives.updateHive(db, hiveId, userId, patch as never),
    softDelete: (hiveId, userId) => queries.hives.softDeleteHive(db, hiveId, userId),
    // 캐시는 best-effort: Redis 장애 시 null/no-op로 DB fallthrough(가용성 우선, §9.6).
    cacheGet: async (userId) => {
      try {
        const raw = await redis.get(hivesCacheKey(userId));
        return raw ? (JSON.parse(raw) as unknown[]) : null;
      } catch {
        return null;
      }
    },
    cacheSet: async (userId, rows) => {
      try {
        await redis.setex(hivesCacheKey(userId), 60, JSON.stringify(rows));
      } catch {
        /* best-effort */
      }
    },
    cacheInvalidate: async (userId) => {
      try {
        await redis.del(hivesCacheKey(userId));
      } catch {
        /* best-effort */
      }
    },
    audit: (entry) => queries.auditLog.appendAuditLog(db, entry),
  };

  const subscriptionsDeps: SubscriptionsDeps = {
    getSubscription: (userId) => queries.accounts.getSubscriptionForUser(db, userId),
    audit: (entry) => queries.auditLog.appendAuditLog(db, entry),
  };

  const inquiriesDeps: InquiriesDeps = {
    create: (input) => queries.inquiries.createInquiry(db, input),
  };

  const adminDeps: AdminDeps = {
    listUsers: (opts) => queries.admin.listUsers(db, opts),
    patchUser: async (input) => {
      try {
        return await queries.admin.patchUser(db, input);
      } catch (e) {
        if (e instanceof queries.admin.SelfDemoteError) {
          throw new AppError('ADMIN_SELF_DEMOTE_FORBIDDEN');
        }
        throw e;
      }
    },
    onBlocked: async (userId) => {
      await queries.auth.revokeAllRefreshTokensForUser(db, userId);
      await bumpSessionsValidAfter(redis, userId);
    },
    listAuditLogs: (opts) => queries.admin.listAuditLogs(db, opts),
    metrics: () => queries.admin.metrics(db),
    getDualByImage: (imageId) => queries.admin.getDualByImage(db, imageId),
  };

  // 보호 미들웨어: requireAuth(alg핀) + sessions_valid_after 즉시 회수 마커(§7.9).
  const protectedAuth = requireAuth(env.JWT_SECRET, {
    isRevoked: (userId, iat) => isSessionRevoked(redis, userId, iat),
  });
  // 인증 사용자 전역 레이트리밋(300/min/user, §7.5). fail-closed.
  const userRateLimit = rateLimit({
    redis,
    limit: 300,
    windowSec: 60,
    prefix: 'user',
    keyFn: (c) => (c.get('userId') as string | undefined) ?? 'anon',
  });
  // 도메인 라우터를 보호 그룹으로 감싸 마운트(컬렉션·하위경로 모두 커버). auth→limiter 순서.
  const protectedMount = (router: Hono) => {
    const g = new Hono();
    g.use('*', protectedAuth);
    g.use('*', userRateLimit);
    g.route('/', router);
    return g;
  };

  // 인증 전 IP 레이트리밋(brute-force 방어, account-protection과 별개 계층, §7.5/§8.5.3).
  const ipLimit = (prefix: string, limit: number) =>
    rateLimit({ redis, limit, windowSec: 60, prefix, keyFn: (c) => getClientIp(c) });

  // Auth: signup/login/refresh 공개(+IP 레이트리밋), logout/me만 보호.
  const authApp = new Hono();
  authApp.use('/signup', ipLimit('signup', 5));
  authApp.use('/login', ipLimit('auth', 10));
  authApp.use('/refresh', ipLimit('auth', 10));
  authApp.use('/logout', protectedAuth);
  authApp.use('/me', protectedAuth);
  authApp.route('/', authRoutes(authDeps));

  // Subscriptions: /plans 공개, /me 보호, /webhook 서명 가드(인증 대신).
  const subsApp = new Hono();
  subsApp.use('/me', protectedAuth);
  subsApp.use(
    '/webhook',
    webhookSignatureGuard({
      secret: env.WEBHOOK_HMAC_SECRET,
      enabled: env.SUBSCRIPTION_WEBHOOK_ENABLED,
    }),
  );
  subsApp.route('/', subscriptionsRoutes(subscriptionsDeps));

  // Inquiries: 익명 공개 라우트. 남용 방지로 5회/시간/IP(브루트포스/스팸 방어). fail-closed.
  const inquiriesApp = new Hono();
  inquiriesApp.use(
    '*',
    rateLimit({ redis, limit: 5, windowSec: 3600, prefix: 'inquiries', keyFn: (c) => getClientIp(c) }),
  );
  inquiriesApp.route('/', inquiriesRoutes(inquiriesDeps));

  // Admin: requireAuth + requireAdmin(role + audience) 단일 마운트(§12.1).
  const adminApp = new Hono();
  adminApp.use('*', protectedAuth);
  adminApp.use('*', requireAdmin(env.JWT_ADMIN_AUDIENCE));
  adminApp.use('*', userRateLimit);
  adminApp.route('/', adminRoutes(adminDeps));

  const app = new Hono();
  app.onError(errorHandler);
  app.use('*', requestId);
  app.use('*', loggerMiddleware());
  app.use('*', corsMiddleware(env.CORS_ALLOWLIST));
  app.use('*', secureHeaders());
  app.get('/health', (c) => c.json({ status: 'ok', timestamp: new Date().toISOString() }));

  app.route('/v1/auth', authApp);
  app.route('/v1/subscriptions', subsApp);
  app.route('/v1/inquiries', inquiriesApp);
  app.route('/v1/hives', protectedMount(hivesRoutes(hivesDeps)));
  app.route('/v1/images', protectedMount(imagesRoutes(imagesDeps)));
  app.route('/v1/analyses', protectedMount(analysesRoutes(analysesDeps)));
  app.route('/v1/admin', adminApp);

  return app;
}
