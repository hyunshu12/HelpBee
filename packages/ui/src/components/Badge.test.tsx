import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Badge } from './Badge';

describe('Badge', () => {
  it('renders label and applies solid variant by default', () => {
    render(<Badge>추천</Badge>);
    const el = screen.getByText('추천');
    expect(el.className).toContain('bg-honey-500');
  });
});
