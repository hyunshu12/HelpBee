import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';

import { Container } from '@/components/Container';
import { DownloadCTABand } from '@/components/DownloadCTABand';
import { SectionHeading } from '@/components/SectionHeading';
import { Hero } from '@/components/home/Hero';
import { HomeFeatureCard } from '@/components/home/HomeFeatureCard';
import { IntroCard } from '@/components/home/IntroCard';
import { RecommendCard } from '@/components/home/RecommendCard';
import { StatsBlock } from '@/components/home/StatsBlock';
import { buildMetadata } from '@/lib/seo';

export function generateMetadata({ params }: { params: { locale: string } }): Metadata {
  return buildMetadata({
    locale: params.locale,
    title: 'HelpBee — AI 벌통 진단',
    description: '스마트폰 하나로 벌통 상태를 정밀 진단하고 최적의 관리 방법을 안내받으세요.',
    path: '',
  });
}

const introIcons = [
  // AI 기반 진단
  <svg key="ai" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <circle cx="12" cy="12" r="9" />
    <path d="M12 7v5l3 2" />
  </svg>,
  // 데이터 보안
  <svg key="security" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z" />
    <path d="M9 12l2 2 4-4" />
  </svg>,
  // 즉각 대응
  <svg key="response" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M13 2L4 14h7l-1 8 9-12h-7z" />
  </svg>,
];

const featureDot = (
  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M5 12l5 5L20 7" />
  </svg>
);

export default function HomePage({ params }: { params: { locale: string } }) {
  setRequestLocale(params.locale);
  const t = useTranslations('home');

  const intro = [0, 1, 2] as const;
  const features = [0, 1, 2, 3] as const;
  const recommends = [0, 1, 2] as const;
  const stats = ['accuracy', 'trust', 'support'] as const;

  return (
    <>
      {/* 1) HERO */}
      <Hero
        title={t('hero.title')}
        subtitle={t('hero.subtitle')}
        cta={t('hero.cta')}
        imageLabel={t('hero.imageLabel')}
      />

      {/* 2) WHAT IS HELPBEE */}
      <section className="py-16 md:py-24">
        <Container>
          <SectionHeading title={t('intro.heading')} />
          <div className="mt-12 grid grid-cols-1 gap-8 md:grid-cols-3">
            {intro.map((i) => (
              <IntroCard
                key={i}
                icon={introIcons[i]}
                title={t(`intro.items.${i}.title`)}
                description={t(`intro.items.${i}.description`)}
              />
            ))}
          </div>
        </Container>
      </section>

      {/* 3) KEY FEATURES */}
      <section className="bg-honey-50 py-16 md:py-24">
        <Container>
          <SectionHeading title={t('features.heading')} />
          <div className="mt-12 grid grid-cols-1 gap-8 md:grid-cols-2">
            {features.map((i) => (
              <HomeFeatureCard
                key={i}
                icon={featureDot}
                title={t(`features.items.${i}.title`)}
                description={t(`features.items.${i}.description`)}
              />
            ))}
          </div>
        </Container>
      </section>

      {/* 4) QUOTE */}
      <section className="py-16 md:py-24">
        <Container>
          <div className="rounded-3xl bg-surface-cream px-8 py-12 text-center md:px-16 md:py-16">
            <p className="mx-auto max-w-3xl text-balance text-2xl font-semibold leading-normal text-bee-black md:text-3xl md:leading-normal">
              {t('quote')}
            </p>
          </div>
        </Container>
      </section>

      {/* 5) RECOMMENDED FOR */}
      <section className="py-16 md:py-24">
        <Container>
          <SectionHeading title={t('recommend.heading')} />
          <div className="mt-12 grid grid-cols-1 gap-8 md:grid-cols-3">
            {recommends.map((i) => (
              <RecommendCard
                key={i}
                imageLabel={t(`recommend.items.${i}.imageLabel`)}
                name={t(`recommend.items.${i}.name`)}
                benefit={t(`recommend.items.${i}.benefit`)}
              />
            ))}
          </div>
        </Container>
      </section>

      {/* 6) STATS */}
      <section className="bg-honey-500/10 py-16 md:py-20">
        <Container>
          <div className="grid grid-cols-1 gap-10 md:grid-cols-3">
            {stats.map((key) => (
              <StatsBlock
                key={key}
                value={t(`stats.${key}.value`)}
                label={t(`stats.${key}.label`)}
              />
            ))}
          </div>
        </Container>
      </section>

      {/* 7) DOWNLOAD CTA BAND */}
      <DownloadCTABand />
    </>
  );
}
