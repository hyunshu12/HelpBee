import { useTranslations } from 'next-intl';

export function SkipLink() {
  const t = useTranslations('common');
  return (
    <a
      href="#main"
      className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[100] focus:rounded-lg focus:bg-honey-500 focus:px-4 focus:py-2 focus:text-white"
    >
      {t('skipToContent')}
    </a>
  );
}
