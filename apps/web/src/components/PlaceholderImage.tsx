import { cn } from '@helpbee/ui';

/** 시안의 회색 이미지 박스 대체 — 실제 에셋 들어오면 next/image로 교체. */
export function PlaceholderImage({
  label,
  className,
}: {
  label?: string;
  className?: string;
}) {
  return (
    <div
      role="img"
      aria-label={label ?? 'image placeholder'}
      className={cn(
        'flex items-center justify-center rounded-2xl bg-bee-black/10 text-center text-bee-black/50',
        className,
      )}
    >
      {label}
    </div>
  );
}
