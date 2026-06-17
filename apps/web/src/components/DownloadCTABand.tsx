import { Button } from '@helpbee/ui';
import { useTranslations } from 'next-intl';

import { Link } from '@/i18n/navigation';
import { Container } from './Container';

export function DownloadCTABand() {
  const t = useTranslations('cta.downloadBand');
  return (
    <section className="bg-honey-500/80">
      <Container className="flex flex-col items-center gap-5 py-16 text-center">
        <h2 className="text-3xl font-extrabold text-white md:text-4xl">{t('title')}</h2>
        <p className="text-lg text-white/90">{t('subtitle')}</p>
        <Link href="/download">
          <Button variant="white" size="lg">
            {t('button')}
          </Button>
        </Link>
      </Container>
    </section>
  );
}
