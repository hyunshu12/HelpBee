import { cn } from '@helpbee/ui';
import type { HTMLAttributes } from 'react';

export function Container({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('mx-auto w-full max-w-6xl px-5 md:px-8', className)} {...props} />;
}
