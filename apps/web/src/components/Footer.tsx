import { useTranslations } from 'next-intl';

import { Link } from '@/i18n/navigation';
import { Container } from './Container';
import { StoreBadge } from './StoreBadge';

export function Footer() {
  const t = useTranslations('footer');

  return (
    <footer className="border-t border-bee-black/10 bg-surface-sand/60">
      <Container className="grid grid-cols-2 gap-8 py-12 md:grid-cols-4">
        <div>
          <h3 className="mb-3 font-bold text-bee-black">{t('columns.service')}</h3>
          <ul className="space-y-2 text-base text-bee-black/70">
            <li>
              <Link href="/">{t('links.serviceIntro')}</Link>
            </li>
            <li>
              <Link href="/how-it-works">{t('links.howItWorks')}</Link>
            </li>
            <li>
              <Link href="/pricing">{t('links.pricing')}</Link>
            </li>
          </ul>
        </div>
        <div>
          <h3 className="mb-3 font-bold text-bee-black">{t('columns.support')}</h3>
          <ul className="space-y-2 text-base text-bee-black/70">
            <li>
              <Link href="/contact">{t('links.help')}</Link>
            </li>
            <li>
              <Link href="/contact">{t('links.contactUs')}</Link>
            </li>
            <li>
              <Link href="/contact">{t('links.faq')}</Link>
            </li>
          </ul>
        </div>
        <div>
          <h3 className="mb-3 font-bold text-bee-black">{t('columns.company')}</h3>
          <ul className="space-y-2 text-base text-bee-black/70">
            <li>
              <Link href="/about">{t('links.about')}</Link>
            </li>
            <li>
              <Link href="/about">{t('links.careers')}</Link>
            </li>
            <li>
              <Link href="/blog">{t('links.blog')}</Link>
            </li>
          </ul>
        </div>
        <div>
          <h3 className="mb-3 font-bold text-bee-black">{t('columns.contact')}</h3>
          <ul className="space-y-2 text-base text-bee-black/70">
            <li>{t('contactInfo.email')}</li>
            <li>{t('contactInfo.phone')}</li>
            <li>{t('contactInfo.address')}</li>
          </ul>
          <div className="mt-4 flex gap-2">
            <StoreBadge store="appstore" />
            <StoreBadge store="playstore" />
          </div>
        </div>
      </Container>
      <Container className="flex flex-col gap-4 border-t border-bee-black/10 py-6 text-sm text-bee-black/60 md:flex-row md:items-center md:justify-between">
        <p>{t('copyright')}</p>
        <div className="flex gap-4">
          <Link href="/privacy">{t('links.privacy')}</Link>
          <Link href="/terms">{t('links.terms')}</Link>
        </div>
      </Container>
    </footer>
  );
}
