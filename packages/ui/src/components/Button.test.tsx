import { render, screen } from '@testing-library/react';
import { createRef } from 'react';
import { describe, expect, it } from 'vitest';
import { Button } from './Button';

describe('Button', () => {
  it('renders its children as a button', () => {
    render(<Button>지금 시작</Button>);
    expect(screen.getByRole('button', { name: '지금 시작' })).toBeInTheDocument();
  });
  it('applies the requested variant class', () => {
    render(<Button variant="outline">x</Button>);
    expect(screen.getByRole('button').className).toContain('border-honey-500');
  });
  it('forwards ref and honors disabled', () => {
    const ref = createRef<HTMLButtonElement>();
    render(
      <Button ref={ref} disabled>
        x
      </Button>,
    );
    expect(ref.current).toBeInstanceOf(HTMLButtonElement);
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
