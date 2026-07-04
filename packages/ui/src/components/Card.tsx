import { forwardRef, type HTMLAttributes } from 'react';
import { cn } from '../utils/cn';

export type CardProps = HTMLAttributes<HTMLDivElement>;

export const Card = forwardRef<HTMLDivElement, CardProps>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn('rounded-2xl bg-white', className)} {...props} />
));
Card.displayName = 'Card';
