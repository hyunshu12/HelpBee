import { describe, expect, it } from 'vitest';
import { cn } from './cn';

describe('cn', () => {
  it('merges conflicting tailwind classes, last wins', () => {
    expect(cn('px-2', 'px-4')).toBe('px-4');
  });
  it('drops falsy values and joins the rest', () => {
    expect(cn('text-bee-black', false && 'hidden', undefined, 'font-bold')).toBe(
      'text-bee-black font-bold',
    );
  });
});
