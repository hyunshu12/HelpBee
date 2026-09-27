/**
 * 라우트 AnalysisWrite(도메인: vdi는 number) → DB NewAnalysis(numeric 컬럼은 string) 명시 변환.
 * 필드를 하나씩 매핑하므로 계약 드리프트(누락·오타)는 type-check에서 실패한다 — `as never` 금지.
 * 신규 insert(createSingleAnalysis)와 failed 재시도 UPDATE(retryFailedAnalysis)가 공유.
 */
import type { NewAnalysis } from '@helpbee/database';

import type { AnalysisWrite } from '../routes/analyses';

export type AnalysisRowWrite = Omit<
  NewAnalysis,
  'id' | 'hiveId' | 'imageId' | 'modelId' | 'createdAt' | 'updatedAt'
>;

function numericOrNull(v: number | null): string | null {
  return v === null || v === undefined ? null : String(v);
}

export function toNewAnalysis(a: AnalysisWrite): Required<AnalysisRowWrite> {
  return {
    status: a.status,
    varroaInfectionRisk: a.varroaInfectionRisk,
    estimatedVarroaCount: a.estimatedVarroaCount,
    overallHealth: a.overallHealth,
    vdi: numericOrNull(a.vdi),
    vdiCiLow: numericOrNull(a.vdiCiLow),
    vdiCiHigh: numericOrNull(a.vdiCiHigh),
    beeTotal: a.beeTotal,
    beeInfested: a.beeInfested,
    rawResponse: a.rawResponse,
    latencyMs: a.latencyMs,
    error: a.error,
    analyzedAt: a.analyzedAt,
  };
}
