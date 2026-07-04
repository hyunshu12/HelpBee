import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';

import { Container } from '@/components/Container';
import { DownloadCTABand } from '@/components/DownloadCTABand';
import { SectionHeading } from '@/components/SectionHeading';
import { PricingCard } from '@/components/pricing/PricingCard';
import { PricingTable } from '@/components/pricing/PricingTable';
import { buildMetadata } from '@/lib/seo';

export function generateMetadata({ params }: { params: { locale: string } }): Metadata {
  return buildMetadata({
    locale: params.locale,
    title: '요금제 — HelpBee',
    description: '베이직·프로·엔터프라이즈 — 나에게 맞는 플랜을 선택하세요. (베타 무료)',
    path: '/pricing',
  });
}

export default function PricingPage({ params }: { params: { locale: string } }) {
  setRequestLocale(params.locale);
  const t = useTranslations('pricing');

  const planKeys = ['basic', 'pro', 'enterprise'] as const;
  const planConfig: Record<
    (typeof planKeys)[number],
    {
      featureCount: number;
      ctaHref: '/download' | '/contact';
      ctaVariant: 'primary' | 'outline';
      recommended: boolean;
    }
  > = {
    basic: { featureCount: 3, ctaHref: '/download', ctaVariant: 'outline', recommended: false },
    pro: { featureCount: 5, ctaHref: '/download', ctaVariant: 'primary', recommended: true },
    enterprise: {
      featureCount: 6,
      ctaHref: '/contact',
      ctaVariant: 'outline',
      recommended: false,
    },
  };

  const tableRowKeys = ['feature1', 'feature2', 'feature3', 'feature4'] as const;
  const benefitKeys = ['benefit1', 'benefit2', 'benefit3'] as const;

  return (
    <>
      {/* 1. Header */}
      <section className="bg-honey-50 py-16 md:py-24">
        <Container className="text-center">
          <h1 className="text-4xl font-extrabold text-bee-black md:text-5xl">{t('header.title')}</h1>
          <p className="mx-auto mt-4 max-w-2xl text-xl text-bee-black/70 md:text-2xl">
            {t('header.subtitle')}
          </p>
          <p className="mx-auto mt-3 max-w-2xl text-lg text-bee-black/60">{t('header.note')}</p>
        </Container>
      </section>

      {/* 2. Plan cards */}
      <section className="py-16 md:py-24">
        <Container>
          <div className="grid grid-cols-1 gap-8 md:grid-cols-3">
            {planKeys.map((key) => {
              const cfg = planConfig[key];
              const features = Array.from({ length: cfg.featureCount }, (_, i) =>
                t(`plans.${key}.features.${i}`),
              );
              return (
                <PricingCard
                  key={key}
                  name={t(`plans.${key}.name`)}
                  description={t(`plans.${key}.description`)}
                  price={t('plans.price')}
                  priceNote={t('plans.priceNote')}
                  features={features}
                  featuresLabel={t('plans.featuresLabel')}
                  ctaLabel={t(`plans.${key}.cta`)}
                  ctaHref={cfg.ctaHref}
                  ctaVariant={cfg.ctaVariant}
                  recommended={cfg.recommended}
                  recommendedLabel={t('plans.recommendedBadge')}
                />
              );
            })}
          </div>
        </Container>
      </section>

      {/* 3. Comparison table */}
      <section className="bg-honey-50 py-16 md:py-24">
        <Container>
          <SectionHeading title={t('compare.title')} className="mb-10" />
          <PricingTable
            columns={{
              feature: t('compare.columns.feature'),
              basic: t('compare.columns.basic'),
              pro: t('compare.columns.pro'),
              enterprise: t('compare.columns.enterprise'),
            }}
            rows={tableRowKeys.map((rowKey) => ({
              label: t(`compare.rows.${rowKey}.label`),
              basic: t(`compare.rows.${rowKey}.basic`),
              pro: t(`compare.rows.${rowKey}.pro`),
              enterprise: t(`compare.rows.${rowKey}.enterprise`),
            }))}
          />
        </Container>
      </section>

      {/* 4. Included benefits */}
      <section className="py-16 md:py-24">
        <Container>
          <SectionHeading title={t('benefits.title')} className="mb-10" />
          <ul className="flex flex-col flex-wrap items-stretch justify-center gap-4 md:flex-row">
            {benefitKeys.map((benefitKey) => (
              <li
                key={benefitKey}
                className="rounded-full bg-surface-pill px-8 py-4 text-center text-lg font-semibold text-bee-black"
              >
                {t(`benefits.${benefitKey}`)}
              </li>
            ))}
          </ul>
        </Container>
      </section>

      {/* 5. Download CTA */}
      <DownloadCTABand
        title={t('cta.title')}
        subtitle={t('cta.subtitle')}
        buttonLabel={t('cta.button')}
      />
    </>
  );
}
