import { Jua } from 'next/font/google';
import localFont from 'next/font/local';

/** 본문/헤딩 — S-Core Dream (에스코어 드림, 무료 배포). self-host woff2. */
export const sans = localFont({
  src: [
    { path: './SCDream4.woff2', weight: '400', style: 'normal' },
    { path: './SCDream5.woff2', weight: '500', style: 'normal' },
    { path: './SCDream6.woff2', weight: '600', style: 'normal' },
    { path: './SCDream7.woff2', weight: '700', style: 'normal' },
    { path: './SCDream8.woff2', weight: '800', style: 'normal' },
  ],
  variable: '--font-sans',
  display: 'swap',
  fallback: ['system-ui', 'sans-serif'],
});

/** 로고 "HelpBee" — Jua (Google Fonts, OFL). */
export const logo = Jua({
  subsets: ['latin'],
  weight: '400',
  variable: '--font-logo',
  display: 'swap',
});
