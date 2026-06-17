import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';

import { Container } from '@/components/Container';
import { DownloadCTABand } from '@/components/DownloadCTABand';
import { buildMetadata } from '@/lib/seo';

export function generateMetadata({ params }: { params: { locale: string } }): Metadata {
  return buildMetadata({
    locale: params.locale,
    title: 'HelpBee — AI 벌통 진단',
    description: '스마트폰 하나로 벌통 상태를 정밀 진단하고 최적의 관리 방법을 안내받으세요.',
    path: '',
  });
}

export default function HomePage({ params }: { params: { locale: string } }) {
  setRequestLocale(params.locale);
  const t = useTranslations('shell');
  return (
    <>
      <Container className="py-24 text-center">
        <h1 className="font-logo text-5xl text-bee-black">HelpBee</h1>
        <p className="mt-4 text-lg text-bee-black/70">{t('ready')}</p>
      </Container>
      <DownloadCTABand />
    </>
  );
}
