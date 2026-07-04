'use client';

import { Button } from '@helpbee/ui';
import { useTranslations } from 'next-intl';
import { useEffect, useState } from 'react';

import { Link } from '@/i18n/navigation';
import { loadAnalytics } from '@/lib/analytics';
import { Container } from './Container';

const STORAGE_KEY = 'hb_cookie_consent';

export function CookieConsent() {
  const t = useTranslations('cookie');
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const consent = localStorage.getItem(STORAGE_KEY);
    if (consent === 'accepted') {
      loadAnalytics();
    } else if (!consent) {
      setVisible(true);
    }
  }, []);

  if (!visible) return null;

  const decide = (accepted: boolean) => {
    localStorage.setItem(STORAGE_KEY, accepted ? 'accepted' : 'declined');
    if (accepted) loadAnalytics();
    setVisible(false);
  };

  return (
    <div className="fixed inset-x-0 bottom-0 z-[80] border-t border-bee-black/10 bg-white/95 backdrop-blur">
      <Container className="flex flex-col gap-3 py-4 md:flex-row md:items-center md:justify-between">
        <p className="text-base text-bee-black/80">
          {t('message')}{' '}
          <Link href="/privacy" className="text-honey-600 underline">
            {t('detail')}
          </Link>
        </p>
        <div className="flex shrink-0 gap-2">
          <Button variant="outline" size="sm" onClick={() => decide(false)}>
            {t('decline')}
          </Button>
          <Button size="sm" onClick={() => decide(true)}>
            {t('accept')}
          </Button>
        </div>
      </Container>
    </div>
  );
}
