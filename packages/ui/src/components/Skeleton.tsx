import { type HTMLAttributes } from 'react';
import { cn } from '../utils/cn';

export type SkeletonProps = HTMLAttributes<HTMLDivElement>;

export function Skeleton({ className, ...props }: SkeletonProps) {
  return <div className={cn('animate-pulse rounded-md bg-honey-100', className)} {...props} />;
}
