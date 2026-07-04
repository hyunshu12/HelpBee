import { forwardRef, type TextareaHTMLAttributes } from 'react';
import { cn } from '../utils/cn';

export type TextareaProps = TextareaHTMLAttributes<HTMLTextAreaElement>;

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(
  ({ className, rows = 5, ...props }, ref) => (
    <textarea
      ref={ref}
      rows={rows}
      className={cn(
        'w-full rounded-2xl border border-black/20 bg-white px-4 py-3 text-lg text-bee-black placeholder:text-black/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-500',
        className,
      )}
      {...props}
    />
  ),
);
Textarea.displayName = 'Textarea';
