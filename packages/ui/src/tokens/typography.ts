/** Fonts are self-hosted by the app and injected via CSS variables.
 *  The preset only references the variable names (spec §4). */
export const fontFamily = {
  sans: ['var(--font-sans)', 'system-ui', 'sans-serif'],
  logo: ['var(--font-logo)', 'var(--font-sans)', 'sans-serif'],
} as const;
