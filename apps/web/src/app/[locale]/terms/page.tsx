import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';

import { LegalContent, type LegalSection } from '@/components/LegalContent';
import { buildMetadata } from '@/lib/seo';

export function generateMetadata({ params }: { params: { locale: string } }): Metadata {
  return buildMetadata({
    locale: params.locale,
    title: '이용약관 — HelpBee',
    description: 'HelpBee 이용약관 (초안).',
    path: '/terms',
  });
}

export default function TermsPage({ params }: { params: { locale: string } }) {
  setRequestLocale(params.locale);
  const t = useTranslations('terms');
  return (
    <LegalContent
      title={t('title')}
      updated={t('updated')}
      intro={t('intro')}
      sections={t.raw('sections') as LegalSection[]}
    />
  );
}
