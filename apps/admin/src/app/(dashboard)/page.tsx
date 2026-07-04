'use client';

import { Skeleton } from '@helpbee/ui';
import { useQuery } from '@tanstack/react-query';

import { Banner } from '@/src/components/Banner';
import { KpiCard, StatRows, StatValue } from '@/src/components/charts/KpiCard';
import { apiFetch } from '@/src/lib/api';
import {
  ANALYSIS_STATUS_LABEL,
  label,
  PLAN_LABEL,
  PROVIDER_LABEL,
} from '@/src/lib/format';
import { queryKeys } from '@/src/lib/query-keys';
import type { AdminMetrics } from '@/src/lib/types';

export default function DashboardPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: queryKeys.metrics(),
    queryFn: () => apiFetch<AdminMetrics>('admin/metrics'),
  });

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-bee-black">대시보드</h1>

      {isError && <Banner tone="error">지표를 불러오지 못했습니다.</Banner>}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {isLoading || !data ? (
          Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-40 rounded-2xl" />)
        ) : (
          <>
            <KpiCard title="전체 사용자">
              <StatValue value={data.users.total} unit="명" />
            </KpiCard>

            <KpiCard title="상태별 분석 수">
              <StatRows
                rows={data.analysesByStatus.map((r) => ({
                  label: label(ANALYSIS_STATUS_LABEL, r.status),
                  count: r.count,
                }))}
              />
            </KpiCard>

            <KpiCard title="엔진별 분석 수 (성공)">
              <StatRows
                rows={data.analysesByProvider.map((r) => ({
                  label: label(PROVIDER_LABEL, r.provider),
                  count: r.count,
                }))}
              />
            </KpiCard>

            <KpiCard title="플랜별 구독">
              <StatRows
                rows={data.subscriptionsByPlan.map((r) => ({
                  label: label(PLAN_LABEL, r.plan),
                  count: r.count,
                }))}
              />
            </KpiCard>
          </>
        )}
      </div>
    </div>
  );
}
