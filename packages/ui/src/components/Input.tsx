import { forwardRef, type InputHTMLAttributes } from 'react';
import { cn } from '../utils/cn';

export type InputProps = InputHTMLAttributes<HTMLInputElement>;

export const Input = forwardRef<HTMLInputElement, InputProps>(({ className, ...props }, ref) => (
  <input
    ref={ref}
    className={cn(
      'h-12 w-full rounded-xl border border-black/20 bg-white px-4 text-lg text-bee-black placeholder:text-[#AFAFAF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-500',
      className,
    )}
    {...props}
  />
));
Input.displayName = 'Input';
