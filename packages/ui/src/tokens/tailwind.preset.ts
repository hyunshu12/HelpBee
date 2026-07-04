import type { Config } from 'tailwindcss';
import { bee, honey, surface } from './colors';
import { fontFamily } from './typography';

/** Single source of truth for the HelpBee palette/typography.
 *  Consumed by apps/web (and later apps/admin) via
 *  `presets: [require('@helpbee/ui/tailwind.preset')]`. */
const preset = {
  theme: {
    extend: {
      colors: {
        honey,
        bee,
        surface,
        primary: honey,
      },
      fontFamily: {
        sans: [...fontFamily.sans],
        logo: [...fontFamily.logo],
      },
      borderRadius: {
        xl: '0.875rem',
        '2xl': '1.25rem',
        '3xl': '1.75rem',
      },
    },
  },
} satisfies Partial<Config>;

export default preset;
