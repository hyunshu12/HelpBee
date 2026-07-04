import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';
import { notFound } from 'next/navigation';

import { Container } from '@/components/Container';
import { getPost, posts } from '@/content/posts';
import { Link } from '@/i18n/navigation';
import { buildMetadata } from '@/lib/seo';

export function generateStaticParams() {
  return posts.map((post) => ({ slug: post.slug }));
}

export function generateMetadata({
  params,
}: {
  params: { locale: string; slug: string };
}): Metadata {
  const post = getPost(params.slug);
  return buildMetadata({
    locale: params.locale,
    title: post ? `${post.title} — HelpBee 블로그` : 'HelpBee 블로그',
    description: post?.excerpt ?? '',
    path: `/blog/${params.slug}`,
  });
}

export default function BlogPostPage({
  params,
}: {
  params: { locale: string; slug: string };
}) {
  setRequestLocale(params.locale);
  const t = useTranslations('blog');
  const post = getPost(params.slug);
  if (!post) notFound();

  return (
    <Container className="max-w-3xl py-16 md:py-24">
      <article>
        <p className="text-sm text-bee-black/50">{post.date}</p>
        <h1 className="mt-2 text-3xl font-bold text-bee-black md:text-4xl">{post.title}</h1>
        <div className="mt-8 space-y-5">
          {post.body.map((para, i) => (
            <p key={i} className="text-lg leading-relaxed text-bee-black/80">
              {para}
            </p>
          ))}
        </div>
      </article>
      <div className="mt-12">
        <Link href="/blog" className="font-semibold text-honey-600 hover:underline">
          ← {t('backToList')}
        </Link>
      </div>
    </Container>
  );
}
