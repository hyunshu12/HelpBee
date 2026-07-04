import { cn } from '@helpbee/ui';
import { forwardRef, type SelectHTMLAttributes } from 'react';

/** 네이티브 select (토큰 스타일). @helpbee/ui에 Select 없음 → 후속에서 ui 패키지로 승격 검토. */
export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(
  ({ className, ...props }, ref) => (
    <select
      ref={ref}
      className={cn(
        'h-12 rounded-xl border border-black/20 bg-white px-3 text-base text-bee-black focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-500',
        className,
      )}
      {...props}
    />
  ),
);
Select.displayName = 'Select';
