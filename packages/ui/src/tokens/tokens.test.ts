import { describe, expect, it } from 'vitest';
import { bee, honey } from './colors';
import preset from './tailwind.preset';

describe('tokens', () => {
  it('anchors honey-500 to the Figma primary', () => {
    expect(honey[500]).toBe('#E49A03');
    expect(bee.black).toBe('#2D1E00');
  });
  it('exposes honey + bee colors and font families on the preset', () => {
    const colors = preset.theme?.extend?.colors as Record<string, unknown>;
    expect(colors.honey).toMatchObject({ 500: '#E49A03' });
    expect(colors.bee).toMatchObject({ black: '#2D1E00' });
    const fonts = preset.theme?.extend?.fontFamily as Record<string, string[]>;
    expect(fonts.sans[0]).toContain('--font-sans');
    expect(fonts.logo[0]).toContain('--font-logo');
  });
});
