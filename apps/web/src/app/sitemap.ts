import type { MetadataRoute } from 'next';

import { posts } from '@/content/posts';

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? 'https://helpbee.kr';

// ko만 색인 (en은 Phase 2 스켈레톤 — sitemap 제외 + noindex, spec §7)
const PATHS = [
  '',
  '/how-it-works',
  '/pricing',
  '/contact',
  '/download',
  '/about',
  '/blog',
  '/privacy',
  '/terms',
  ...posts.map((p) => `/blog/${p.slug}`),
];

export default function sitemap(): MetadataRoute.Sitemap {
  return PATHS.map((path) => ({
    url: `${SITE_URL}/ko${path}`,
    changeFrequency: 'weekly',
    priority: path === '' ? 1 : 0.7,
  }));
}
