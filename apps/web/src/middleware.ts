import createMiddleware from 'next-intl/middleware';
import { routing } from './i18n/routing';

export default createMiddleware(routing);

export const config = {
  // 모든 경로에 적용하되 api/_next/_vercel 및 파일(.확장자)은 제외
  matcher: ['/((?!api|_next|_vercel|.*\\..*).*)'],
};
