import { z } from 'zod';

// zod 버전 견고한 uuid 검증(zod v4의 .string().uuid() API 변동 회피)
const uuid = z
  .string()
  .regex(
    /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/,
    'invalid uuid',
  );

export const createAnalysisSchema = z
  .object({
    hiveId: uuid,
    imageId: uuid,
  })
  .strict(); // 모르는 키 거부 (Mass Assignment 차단)

// hiveId 생략 = 내 모든 벌통의 진단 이력(최신순). 모바일 "진단 이력" 탭이 쓴다.
// 지정하면 기존대로 해당 벌통만. 어느 쪽이든 소유권은 쿼리의 hives JOIN이 강제.
export const listAnalysesQuerySchema = z.object({
  hiveId: uuid.optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

export const trendQuerySchema = z.object({
  hiveId: uuid,
  from: z.string().optional(), // ISO; 미지정 시 최근 30일
  to: z.string().optional(),
});

export type CreateAnalysisInput = z.infer<typeof createAnalysisSchema>;
