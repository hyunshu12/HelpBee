'use client';

import { Input, cn } from '@helpbee/ui';
import { useTranslations } from 'next-intl';
import { useId, useMemo, useState } from 'react';

import { Link } from '@/i18n/navigation';

const FAQ_KEYS = ['analyze', 'accuracy', 'offline', 'free', 'privacy'] as const;

type FaqItem = { question: string; answer: string };

/** 질문 검색 + 접근성 아코디언. 외부 deps 없이 useState로 펼침 상태 관리. */
export function FaqList() {
  const t = useTranslations('contact');
  const baseId = useId();
  const [query, setQuery] = useState('');
  const [openIndex, setOpenIndex] = useState<number | null>(0);

  const items: FaqItem[] = useMemo(
    () =>
      FAQ_KEYS.map((key) => ({
        question: t(`faq.items.${key}.q`),
        answer: t(`faq.items.${key}.a`),
      })),
    [t],
  );

  const normalized = query.trim().toLowerCase();
  const filtered = useMemo(
    () =>
      normalized.length === 0
        ? items
        : items.filter(
            (item) =>
              item.question.toLowerCase().includes(normalized) ||
              item.answer.toLowerCase().includes(normalized),
          ),
    [items, normalized],
  );

  return (
    <div className="mx-auto mt-10 max-w-3xl">
      <Input
        type="search"
        value={query}
        onChange={(e) => {
          setQuery(e.target.value);
          setOpenIndex(null);
        }}
        placeholder={t('faq.searchPlaceholder')}
        aria-label={t('faq.searchPlaceholder')}
      />

      <ul className="mt-6 flex flex-col gap-3">
        {filtered.length === 0 ? (
          <li className="rounded-2xl bg-surface-cream px-5 py-6 text-center text-lg text-bee-black/60">
            {t('faq.empty')}
          </li>
        ) : (
          filtered.map((item, index) => {
            const isOpen = openIndex === index;
            const buttonId = `${baseId}-faq-btn-${index}`;
            const panelId = `${baseId}-faq-panel-${index}`;
            return (
              <li
                key={item.question}
                className="overflow-hidden rounded-2xl border border-honey-100 bg-white"
              >
                <h3 className="m-0">
                  <button
                    type="button"
                    id={buttonId}
                    aria-expanded={isOpen}
                    aria-controls={panelId}
                    onClick={() => setOpenIndex(isOpen ? null : index)}
                    className="flex w-full items-center justify-between gap-4 px-6 py-5 text-left text-lg font-semibold text-bee-black focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-500"
                  >
                    <span>{item.question}</span>
                    <span
                      aria-hidden="true"
                      className={cn(
                        'shrink-0 text-2xl text-honey-600 transition-transform duration-200',
                        isOpen && 'rotate-45',
                      )}
                    >
                      +
                    </span>
                  </button>
                </h3>
                <div
                  id={panelId}
                  role="region"
                  aria-labelledby={buttonId}
                  hidden={!isOpen}
                  className="px-6 pb-5 text-lg leading-relaxed text-bee-black/70"
                >
                  {item.answer}
                </div>
              </li>
            );
          })
        )}
      </ul>

      <div className="mt-6 text-center">
        <Link
          href="/contact"
          className="text-lg font-semibold text-honey-600 underline-offset-4 hover:underline"
        >
          {t('faq.viewAll')}
        </Link>
      </div>
    </div>
  );
}
