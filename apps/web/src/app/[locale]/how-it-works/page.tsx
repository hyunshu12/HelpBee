import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';

import { Container } from '@/components/Container';
import { DownloadCTABand } from '@/components/DownloadCTABand';
import { PlaceholderImage } from '@/components/PlaceholderImage';
import { StepRow } from '@/components/how-it-works/StepRow';
import { TipBox } from '@/components/how-it-works/TipBox';
import { buildMetadata } from '@/lib/seo';

export function generateMetadata({ params }: { params: { locale: string } }): Metadata {
  return buildMetadata({
    locale: params.locale,
    title: '이용 방법 — HelpBee',
    description: '촬영 → 분석 → 결과 3단계로 간편하게 벌통을 진단하세요.',
    path: '/how-it-works',
  });
}

export default function HowItWorksPage({ params }: { params: { locale: string } }) {
  setRequestLocale(params.locale);
  const t = useTranslations('howItWorks');

  const tipItems = [
    t('steps.capture.tip.items.bright'),
    t('steps.capture.tip.items.whole'),
    t('steps.capture.tip.items.sharp'),
    t('steps.capture.tip.items.guide'),
  ];

  return (
    <>
      {/* HERO */}
      <section className="bg-honey-50 py-16 md:py-24">
        <Container className="flex flex-col items-center gap-10">
          <div className="text-center">
            <h1 className="text-4xl font-bold text-bee-black md:text-5xl">{t('hero.title')}</h1>
            <p className="mt-4 text-xl font-semibold text-honey-600 md:text-2xl">
              {t('hero.subtitle')}
            </p>
            <p className="mx-auto mt-4 max-w-2xl text-lg text-bee-black/70">{t('hero.intro')}</p>
          </div>
          <PlaceholderImage
            label={t('hero.imageLabel')}
            className="aspect-[16/9] w-full max-w-4xl text-lg"
          />
        </Container>
      </section>

      {/* THREE STEPS */}
      <section className="py-16 md:py-24">
        <Container className="flex flex-col gap-16 md:gap-24">
          <StepRow
            number="01"
            title={t('steps.capture.title')}
            description={t('steps.capture.description')}
            screenLabel={t('steps.capture.screenLabel')}
          >
            <TipBox title={t('steps.capture.tip.title')} items={tipItems} />
          </StepRow>

          <StepRow
            number="02"
            title={t('steps.analyze.title')}
            description={t('steps.analyze.description')}
            screenLabel={t('steps.analyze.screenLabel')}
            reverse
          />

          <StepRow
            number="03"
            title={t('steps.result.title')}
            description={t('steps.result.description')}
            screenLabel={t('steps.result.screenLabel')}
          />
        </Container>
      </section>

      {/* BOTTOM CTA */}
      <DownloadCTABand
        title={t('cta.title')}
        subtitle={t('cta.subtitle')}
        buttonLabel={t('cta.button')}
      />
    </>
  );
}
