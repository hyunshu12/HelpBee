import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';

import { Container } from '@/components/Container';
import { PlaceholderImage } from '@/components/PlaceholderImage';
import { buildMetadata } from '@/lib/seo';

export function generateMetadata({ params }: { params: { locale: string } }): Metadata {
  return buildMetadata({
    locale: params.locale,
    title: '회사 소개 — HelpBee',
    description: 'HelpBee의 미션과 이야기를 소개합니다.',
    path: '/about',
  });
}

export default function AboutPage({ params }: { params: { locale: string } }) {
  setRequestLocale(params.locale);
  const t = useTranslations('about');
  const blocks = t.raw('blocks') as { heading: string; body: string }[];
  return (
    <Container className="max-w-4xl py-16 md:py-24">
      <header className="text-center">
        <h1 className="text-4xl font-bold text-bee-black md:text-5xl">{t('title')}</h1>
        <p className="mt-4 text-lg text-bee-black/70 md:text-xl">{t('subtitle')}</p>
      </header>
      <PlaceholderImage label={t('teamLabel')} className="mt-10 aspect-[16/9] w-full" />
      <div className="mt-12 space-y-10">
        {blocks.map((b, i) => (
          <section key={i}>
            <h2 className="text-2xl font-bold text-bee-black">{b.heading}</h2>
            <p className="mt-3 text-lg leading-relaxed text-bee-black/80">{b.body}</p>
          </section>
        ))}
      </div>
    </Container>
  );
}
