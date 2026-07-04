import type { ReactNode } from 'react';

import { cn } from '@helpbee/ui';

import { PlaceholderImage } from '@/components/PlaceholderImage';

/**
 * 3단계 진단 흐름의 한 행. 데스크톱에서 이미지/텍스트를 좌우 교차 배치(reverse),
 * 모바일에서는 위아래로 쌓는다. 큰 숫자 배지(01/02/03) + 제목 + 설명 + 화면 플레이스홀더.
 */
export function StepRow({
  number,
  title,
  description,
  screenLabel,
  reverse = false,
  children,
}: {
  number: string;
  title: string;
  description: string;
  screenLabel: string;
  reverse?: boolean;
  children?: ReactNode;
}) {
  return (
    <div className="grid grid-cols-1 items-center gap-8 md:grid-cols-2 md:gap-12">
      {/* 텍스트 영역 */}
      <div className={cn('flex flex-col', reverse && 'md:order-2')}>
        <span className="text-4xl font-extrabold text-honey-500 md:text-5xl">{number}</span>
        <h3 className="mt-3 text-2xl font-bold text-bee-black md:text-3xl">{title}</h3>
        <p className="mt-4 text-lg leading-relaxed text-bee-black/70">{description}</p>
        {children ? <div className="mt-6">{children}</div> : null}
      </div>

      {/* 화면 플레이스홀더 영역 */}
      <div className={cn('flex justify-center', reverse && 'md:order-1')}>
        <PlaceholderImage
          label={screenLabel}
          className="aspect-[9/16] w-full max-w-[280px] text-lg"
        />
      </div>
    </div>
  );
}
