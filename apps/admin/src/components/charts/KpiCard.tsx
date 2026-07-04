import { Card } from '@helpbee/ui';
import type { ReactNode } from 'react';

/** KPI 카드. Recharts는 MVP 미도입 — 집계 수치는 카드/목록으로 표시(CLAUDE.md Decision Log). */
export function KpiCard({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <Card className="space-y-3 p-6 shadow-sm">
      <h3 className="text-sm font-semibold text-bee-brown">{title}</h3>
      {children}
    </Card>
  );
}

export function StatValue({ value, unit }: { value: number | string; unit?: string }) {
  return (
    <p className="text-3xl font-bold text-bee-black">
      {value}
      {unit && <span className="ml-1 text-lg font-medium text-bee-brown">{unit}</span>}
    </p>
  );
}

export function StatRows({ rows }: { rows: { label: string; count: number }[] }) {
  if (rows.length === 0) return <p className="text-base text-bee-brown">데이터 없음</p>;
  return (
    <ul className="space-y-1.5">
      {rows.map((r) => (
        <li key={r.label} className="flex items-center justify-between text-base">
          <span className="text-bee-brown">{r.label}</span>
          <span className="font-semibold text-bee-black">{r.count}</span>
        </li>
      ))}
    </ul>
  );
}
