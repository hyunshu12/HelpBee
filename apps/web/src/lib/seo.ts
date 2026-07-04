import type { Metadata } from 'next';
import { routing } from '@/i18n/routing';

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? 'https://helpbee.kr';

export type BuildMetadataInput = {
  locale: string;
  title: string;
  description: string;
  /** locale 뒤에 붙는 경로 (예: '/pricing'). 홈은 '' */
  path?: string;
};

export function buildMetadata({
  locale,
  title,
  description,
  path = '',
}: BuildMetadataInput): Metadata {
  const url = `${SITE_URL}/${locale}${path}`;
  const languages: Record<string, string> = {};
  routing.locales.forEach((l) => {
    languages[l] = `${SITE_URL}/${l}${path}`;
  });

  return {
    title,
    description,
    metadataBase: new URL(SITE_URL),
    alternates: { canonical: url, languages },
    openGraph: { title, description, url, siteName: 'HelpBee', locale, type: 'website' },
    // en은 Phase 2 스켈레톤 — 색인 차단 (spec §7)
    robots: locale === 'en' ? { index: false, follow: false } : undefined,
  };
}
