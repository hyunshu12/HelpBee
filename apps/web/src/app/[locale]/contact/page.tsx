import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';

import { Container } from '@/components/Container';
import { SectionHeading } from '@/components/SectionHeading';
import { ContactChannels } from '@/components/contact/ContactChannels';
import { ContactForm } from '@/components/contact/ContactForm';
import { FaqList } from '@/components/contact/FaqList';
import { DownloadCTABand } from '@/components/DownloadCTABand';
import { buildMetadata } from '@/lib/seo';

export function generateMetadata({ params }: { params: { locale: string } }): Metadata {
  return buildMetadata({
    locale: params.locale,
    title: '문의하기 — HelpBee',
    description: '자주 묻는 질문과 1:1 문의. 24시간 이내 답변드립니다.',
    path: '/contact',
  });
}

export default function ContactPage({ params }: { params: { locale: string } }) {
  setRequestLocale(params.locale);
  const t = useTranslations('contact');

  return (
    <>
      {/* 1) HEADER */}
      <section className="bg-honey-50 py-16 md:py-24">
        <Container className="text-center">
          <h1 className="text-4xl font-bold text-bee-black md:text-5xl">{t('header.title')}</h1>
          <p className="mt-4 text-lg text-bee-black/70 md:text-xl">{t('header.subtitle')}</p>
        </Container>
      </section>

      {/* 2) FAQ */}
      <section className="py-16 md:py-24">
        <Container>
          <SectionHeading title={t('faq.title')} />
          <FaqList />
        </Container>
      </section>

      {/* 3) DIRECT CONTACT — channels */}
      <section className="bg-surface-cream py-16 md:py-24">
        <Container>
          <SectionHeading title={t('direct.title')} subtitle={t('direct.subtitle')} />
          <ContactChannels />
        </Container>
      </section>

      {/* 4) CONTACT FORM */}
      <section className="py-16 md:py-24">
        <Container>
          <SectionHeading title={t('form.title')} subtitle={t('form.subtitle')} />
          <ContactForm />
        </Container>
      </section>

      <DownloadCTABand
        title={t('ctaBand.title')}
        subtitle={t('ctaBand.subtitle')}
        buttonLabel={t('ctaBand.button')}
      />
    </>
  );
}
