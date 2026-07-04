import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Card } from './Card';

describe('Card', () => {
  it('renders children inside a rounded container and merges className', () => {
    render(<Card className="p-8">내용</Card>);
    const el = screen.getByText('내용');
    expect(el.className).toContain('rounded-2xl');
    expect(el.className).toContain('p-8');
  });
});
