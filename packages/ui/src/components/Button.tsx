import { cva, type VariantProps } from 'class-variance-authority';
import { forwardRef, type ButtonHTMLAttributes } from 'react';
import { cn } from '../utils/cn';

const buttonVariants = cva(
  'inline-flex items-center justify-center font-semibold transition-colors rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-500 focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none',
  {
    variants: {
      variant: {
        primary: 'bg-honey-500 text-white hover:bg-honey-600',
        outline: 'border border-honey-500 text-honey-600 bg-transparent hover:bg-honey-50',
        white: 'bg-white text-bee-black shadow-sm hover:bg-honey-50',
        ghost: 'text-bee-black hover:bg-honey-50',
      },
      size: {
        sm: 'h-10 px-4 text-base',
        md: 'h-12 px-6 text-lg',
        lg: 'h-14 px-8 text-xl',
      },
    },
    defaultVariants: { variant: 'primary', size: 'md' },
  },
);

export interface ButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, type = 'button', ...props }, ref) => (
    <button
      ref={ref}
      type={type}
      className={cn(buttonVariants({ variant, size }), className)}
      {...props}
    />
  ),
);
Button.displayName = 'Button';

export { buttonVariants };
