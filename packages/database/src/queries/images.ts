import { and, eq, isNull } from 'drizzle-orm';

import type { Database } from '../client';
import {
  type AnalysisImage,
  analysisImages,
  type NewAnalysisImage,
} from '../schema/analysisImages';
import { hives } from '../schema/hives';

/** confirm 단계: 검증·strip 완료된 이미지 메타 저장. */
export async function createAnalysisImage(
  db: Database,
  input: NewAnalysisImage,
): Promise<AnalysisImage> {
  const [row] = await db.insert(analysisImages).values(input).returning();
  if (!row) {
    throw new Error('[createAnalysisImage] insert returned no row');
  }
  return row;
}

/**
 * 이미지 단일 조회 (소유권 검증). uploaded_by=userId AND hive.userId=userId AND
 * hive 미삭제. 비소유/없음 → undefined → 라우트 404 (IDOR 차단).
 */
export async function getAnalysisImageByIdForUser(
  db: Database,
  imageId: string,
  userId: string,
): Promise<AnalysisImage | undefined> {
  const rows = await db
    .select({ img: analysisImages })
    .from(analysisImages)
    .innerJoin(hives, eq(hives.id, analysisImages.hiveId))
    .where(
      and(
        eq(analysisImages.id, imageId),
        eq(analysisImages.uploadedBy, userId),
        eq(hives.userId, userId),
        isNull(hives.deletedAt),
      ),
    )
    .limit(1);
  return rows[0]?.img;
}
