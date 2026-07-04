/** Figma-derived palette (spec §4). honey-500 = Figma primary #E49A03. */
export const honey = {
  50: '#FFFBF0',
  100: '#FFEDC7',
  200: '#FBE3A8',
  300: '#F7C863',
  400: '#F0B23B',
  500: '#E49A03',
  600: '#C2850A',
  700: '#9B6A08',
  800: '#74500A',
  900: '#4D360A',
} as const;

export const bee = {
  black: '#2D1E00', // headings / strong text
  brown: '#6B4423', // secondary text
} as const;

/** Warm surface tints observed in the Figma frames. */
export const surface = {
  cream: '#FFF1CE', // gradient / hero wash
  sand: '#E4D3B9', // footer band
  tip: '#FFEECB', // TIP box (how-it-works)
  pill: '#FCF5E0', // benefit pills (pricing)
  row: '#F9EBD0', // compare-table row
} as const;
