import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';

import { LegalContent, type LegalSection } from '@/components/LegalContent';
import { buildMetadata } from '@/lib/seo';

export function generateMetadata({ params }: { params: { locale: string } }): Metadata {
  return buildMetadata({
    locale: params.locale,
    title: '개인정보처리방침 — HelpBee',
    description: 'HelpBee 개인정보처리방침 (초안).',
    path: '/privacy',
  });
}

export default function PrivacyPage({ params }: { params: { locale: string } }) {
  setRequestLocale(params.locale);
  const t = useTranslations('privacy');
  return (
    <LegalContent
      title={t('title')}
      updated={t('updated')}
      intro={t('intro')}
      sections={t.raw('sections') as LegalSection[]}
    />
  );
}
