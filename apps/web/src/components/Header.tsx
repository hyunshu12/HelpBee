'use client';

import { Button } from '@helpbee/ui';
import { useTranslations } from 'next-intl';
import { useState } from 'react';

import { Link } from '@/i18n/navigation';
import { Container } from './Container';
import { LanguageSwitcher } from './LanguageSwitcher';

const NAV = [
  { key: 'service', href: '/' },
  { key: 'howItWorks', href: '/how-it-works' },
  { key: 'pricing', href: '/pricing' },
  { key: 'contact', href: '/contact' },
] as const;

export function Header() {
  const t = useTranslations('nav');
  const [open, setOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-bee-black/5 bg-white/90 backdrop-blur">
      <Container className="flex h-[72px] items-center justify-between gap-4">
        <Link
          href="/"
          className="font-logo text-2xl text-bee-black"
          onClick={() => setOpen(false)}
        >
          HelpBee
        </Link>

        <nav className="hidden items-center gap-8 md:flex">
          {NAV.map((item) => (
            <Link
              key={item.key}
              href={item.href}
              className="text-lg text-bee-black/80 transition-colors hover:text-bee-black"
            >
              {t(item.key)}
            </Link>
          ))}
        </nav>

        <div className="hidden items-center gap-3 md:flex">
          <LanguageSwitcher />
          <Link href="/download">
            <Button size="sm">{t('download')}</Button>
          </Link>
        </div>

        <button
          type="button"
          className="inline-flex h-11 w-11 items-center justify-center rounded-lg text-bee-black md:hidden"
          aria-label="Menu"
          aria-expanded={open}
          onClick={() => setOpen((v) => !v)}
        >
          <svg
            width="26"
            height="26"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
          >
            {open ? (
              <>
                <line x1="6" y1="6" x2="18" y2="18" />
                <line x1="6" y1="18" x2="18" y2="6" />
              </>
            ) : (
              <>
                <line x1="4" y1="7" x2="20" y2="7" />
                <line x1="4" y1="12" x2="20" y2="12" />
                <line x1="4" y1="17" x2="20" y2="17" />
              </>
            )}
          </svg>
        </button>
      </Container>

      {open && (
        <div className="border-t border-bee-black/5 bg-white md:hidden">
          <Container className="flex flex-col gap-1 py-3">
            {NAV.map((item) => (
              <Link
                key={item.key}
                href={item.href}
                className="rounded-lg px-2 py-3 text-lg text-bee-black/80 hover:bg-honey-50"
                onClick={() => setOpen(false)}
              >
                {t(item.key)}
              </Link>
            ))}
            <div className="mt-2 flex items-center justify-between">
              <LanguageSwitcher />
              <Link href="/download" onClick={() => setOpen(false)}>
                <Button size="sm">{t('download')}</Button>
              </Link>
            </div>
          </Container>
        </div>
      )}
    </header>
  );
}
