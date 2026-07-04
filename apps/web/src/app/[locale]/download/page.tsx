import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';

import { Container } from '@/components/Container';
import { PlaceholderImage } from '@/components/PlaceholderImage';
import { StoreBadge } from '@/components/StoreBadge';
import { buildMetadata } from '@/lib/seo';

export function generateMetadata({ params }: { params: { locale: string } }): Metadata {
  return buildMetadata({
    locale: params.locale,
    title: '앱 다운로드 — HelpBee',
    description: '지금 HelpBee를 설치하고 스마트폰으로 벌통 건강을 진단하세요.',
    path: '/download',
  });
}

export default function DownloadPage({ params }: { params: { locale: string } }) {
  setRequestLocale(params.locale);
  const t = useTranslations('download');
  return (
    <Container className="flex flex-col items-center gap-8 py-20 text-center md:py-28">
      <h1 className="text-4xl font-bold text-bee-black md:text-5xl">{t('title')}</h1>
      <p className="max-w-2xl text-lg text-bee-black/70 md:text-xl">{t('subtitle')}</p>
      <div className="flex flex-wrap items-center justify-center gap-3">
        <StoreBadge store="appstore" />
        <StoreBadge store="playstore" />
      </div>
      <PlaceholderImage label={t('qrLabel')} className="h-44 w-44" />
      <p className="text-base text-bee-black/50">{t('note')}</p>
    </Container>
  );
}
