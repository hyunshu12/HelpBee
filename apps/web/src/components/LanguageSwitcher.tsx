'use client';

import { useLocale } from 'next-intl';
import { usePathname, useRouter } from '@/i18n/navigation';

export function LanguageSwitcher() {
  const locale = useLocale();
  const router = useRouter();
  const pathname = usePathname();
  const next = locale === 'ko' ? 'en' : 'ko';

  return (
    <button
      type="button"
      onClick={() => router.replace(pathname, { locale: next })}
      className="rounded-full border border-bee-black/15 px-3 py-1 text-sm font-medium text-bee-black/80 transition-colors hover:bg-honey-50"
      aria-label="Change language"
    >
      {locale === 'ko' ? 'EN' : '한국어'}
    </button>
  );
}
