import { render, screen } from '@testing-library/react';
import { createRef } from 'react';
import { describe, expect, it } from 'vitest';
import { Input } from './Input';

describe('Input', () => {
  it('forwards ref (RHF register compatible) and spreads props', () => {
    const ref = createRef<HTMLInputElement>();
    render(<Input ref={ref} placeholder="이름" />);
    expect(ref.current).toBeInstanceOf(HTMLInputElement);
    expect(screen.getByPlaceholderText('이름')).toBeInTheDocument();
  });
});
