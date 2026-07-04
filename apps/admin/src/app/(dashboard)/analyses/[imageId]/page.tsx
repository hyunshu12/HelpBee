'use client';

import { Badge, Card, Skeleton } from '@helpbee/ui';
import { useQuery } from '@tanstack/react-query';
import { useParams } from 'next/navigation';

import { Banner } from '@/src/components/Banner';
import { apiFetch } from '@/src/lib/api';
import { ApiError } from '@/src/lib/errors';
import { ANALYSIS_STATUS_LABEL, HEALTH_LABEL, label, PROVIDER_LABEL } from '@/src/lib/format';
import { queryKeys } from '@/src/lib/query-keys';
import type { DualComparison, DualEngineRow } from '@/src/lib/types';

/**
 * 두 엔진(YOLO=primary / OpenAI=secondary) 진단 비교. 링크 진입점은 아직 없음 → 직접 URL 접근.
 * ⚠️ 현재 AI 추론 미동작(§10) — 실데이터가 없으면 NOT_FOUND. bbox 오버레이(Canvas)는 후속 과제.
 */
export default function DualAnalysisPage() {
  const { imageId } = useParams<{ imageId: string }>();
  const { data, isLoading, isError, error } = useQuery({
    queryKey: queryKeys.dual(imageId),
    queryFn: () => apiFetch<DualComparison>(`admin/analyses/${imageId}/dual`),
  });

  if (isLoading) return <Skeleton className="h-72 rounded-2xl" />;

  if (isError) {
    const notFound = error instanceof ApiError && error.status === 404;
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-bee-black">진단 비교</h1>
        <Banner tone={notFound ? 'info' : 'error'}>
          {notFound ? '두 엔진 결과가 아직 없습니다.' : '진단 비교를 불러오지 못했습니다.'}
        </Banner>
      </div>
    );
  }

  if (!data) return null;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-bee-black">진단 비교</h1>

      {data.agreement && (
        <div className="flex flex-wrap items-center gap-3">
          <Badge variant={data.agreement.healthMatch ? 'soft' : 'solid'}>
            건강도 {data.agreement.healthMatch ? '일치' : '불일치'}
          </Badge>
          {data.agreement.riskDiff != null && (
            <Badge variant="soft">위험도 차이 {data.agreement.riskDiff}</Badge>
          )}
        </div>
      )}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <EngineCard title="Primary (YOLO)" row={data.primary} />
        {data.secondary ? (
          <EngineCard title="Secondary (OpenAI)" row={data.secondary} />
        ) : (
          <Card className="flex items-center justify-center p-6 text-bee-brown shadow-sm">
            보조 엔진 결과가 없습니다.
          </Card>
        )}
      </div>
    </div>
  );
}

function EngineCard({ title, row }: { title: string; row: DualEngineRow }) {
  return (
    <Card className="space-y-3 p-6 shadow-sm">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-bee-black">{title}</h2>
        <Badge variant="soft">{label(PROVIDER_LABEL, row.provider)}</Badge>
      </div>
      <dl className="grid grid-cols-2 gap-3">
        <Field label="모델" value={`${row.modelName} ${row.modelVersion}`} />
        <Field label="상태" value={label(ANALYSIS_STATUS_LABEL, row.status)} />
        <Field
          label="응애 위험도"
          value={row.varroaInfectionRisk != null ? String(row.varroaInfectionRisk) : '-'}
        />
        <Field label="건강도" value={label(HEALTH_LABEL, row.overallHealth)} />
      </dl>
      {row.rawResponse && Object.keys(row.rawResponse).length > 0 && (
        <div>
          <p className="mb-1 text-sm text-bee-brown">원본 응답(화이트리스트)</p>
          <pre className="max-h-48 overflow-auto whitespace-pre-wrap break-all rounded-lg bg-honey-50 p-2 text-xs">
            {JSON.stringify(row.rawResponse, null, 2)}
          </pre>
        </div>
      )}
    </Card>
  );
}

function Field({ label: l, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-sm text-bee-brown">{l}</dt>
      <dd className="text-base font-semibold text-bee-black">{value}</dd>
    </div>
  );
}
