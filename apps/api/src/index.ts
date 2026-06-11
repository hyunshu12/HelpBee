/**
 * 부트스트랩 — @hono/node-server로 listen만 담당. 앱 구성은 app.ts(createApp).
 * createApp()이 env fail-fast 검증 → 누락 시 부팅 거부.
 */
import { serve } from '@hono/node-server';

import { createApp } from './app';

const port = parseInt(process.env.PORT ?? '3001', 10);
const app = createApp();

serve({ fetch: app.fetch, port });
// eslint-disable-next-line no-console
console.log(`🚀 API Server running on http://localhost:${port}`);

export default app;
