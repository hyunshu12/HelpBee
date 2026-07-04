'use client';

import { cn } from '@helpbee/ui';

/** 간단한 인라인 알림 배너 (toast 라이브러리 대체 — MVP). */
export function Banner({
  tone = 'info',
  children,
  className,
}: {
  tone?: 'info' | 'success' | 'error';
  children: React.ReactNode;
  className?: string;
}) {
  const tones = {
    info: 'bg-honey-100 text-honey-800',
    success: 'bg-green-100 text-green-800',
    error: 'bg-red-100 text-red-800',
  };
  return (
    <div role="status" className={cn('rounded-xl px-4 py-3 text-base', tones[tone], className)}>
      {children}
    </div>
  );
}
