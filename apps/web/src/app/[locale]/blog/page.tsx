import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';

import { Container } from '@/components/Container';
import { posts } from '@/content/posts';
import { Link } from '@/i18n/navigation';
import { buildMetadata } from '@/lib/seo';

export function generateMetadata({ params }: { params: { locale: string } }): Metadata {
  return buildMetadata({
    locale: params.locale,
    title: '블로그 — HelpBee',
    description: '양봉·꿀벌 응애·AI 진단에 관한 가이드와 소식.',
    path: '/blog',
  });
}

export default function BlogIndexPage({ params }: { params: { locale: string } }) {
  setRequestLocale(params.locale);
  const t = useTranslations('blog');
  return (
    <Container className="max-w-4xl py-16 md:py-24">
      <header className="text-center">
        <h1 className="text-4xl font-bold text-bee-black md:text-5xl">{t('title')}</h1>
        <p className="mt-4 text-lg text-bee-black/70 md:text-xl">{t('subtitle')}</p>
      </header>
      <div className="mt-12 grid grid-cols-1 gap-6">
        {posts.map((post) => (
          <Link
            key={post.slug}
            href={`/blog/${post.slug}`}
            className="block rounded-2xl border border-honey-100 bg-white p-6 transition-colors hover:bg-honey-50 md:p-8"
          >
            <p className="text-sm text-bee-black/50">{post.date}</p>
            <h2 className="mt-2 text-2xl font-bold text-bee-black">{post.title}</h2>
            <p className="mt-2 text-lg text-bee-black/70">{post.excerpt}</p>
            <span className="mt-4 inline-block font-semibold text-honey-600">{t('readMore')}</span>
          </Link>
        ))}
      </div>
    </Container>
  );
}
