# 2026-06-17 — 웹 프론트엔드 MVP (apps/web) + 디자인 시스템(@helpbee/ui) 기반

> PR: (예정) · 브랜치: feature/web-frontend-mvp → develop · 머지일: (예정)

## 범위 (Scope)

방금 완성된 **Figma 데스크톱 시안 4프레임을 진실의 원천**으로 삼아, 거의 비어있던 `@helpbee/ui`와 `apps/web`을 바닥부터 구축해 **마케팅/콘텐츠 웹사이트 MVP**를 완성(반응형, ko 기본 + en 골격 noindex, 콘텐츠 더미).

## 산출물 (Deliverables)

### @helpbee/ui (디자인 시스템 기반)
- `src/tokens/colors.ts` · `typography.ts` · `tailwind.preset.ts` — **Figma 팔레트 단일 소스** (honey-500 = `#E49A03`, bee-black `#2D1E00`, surface tints, S-Core Dream/Jua 폰트 변수)
- `src/utils/cn.ts` — clsx + tailwind-merge
- `src/components/` — Button·Card·Badge·Input·Textarea·Skeleton (cva + forwardRef)
- `src/index.ts` 배럴, `package.json` exports(`.` + `./tailwind.preset`), vitest 4 + RTL 셋업
- 테스트 12개(cn·tokens·각 프리미티브)

### apps/web (Next.js 14 App Router)
- 셸: `next.config.js`(next-intl 플러그인) · `tailwind.config.ts`(preset 상속) · `src/middleware.ts` · `src/i18n/{routing,navigation,request}.ts` · `src/app/[locale]/layout.tsx`
- 폰트: `src/fonts/`(S-Core Dream `SCDream4~8.woff2` self-host + Jua via next/font) — `--font-sans`/`--font-logo`
- 글로벌 컴포넌트: `Header`(모바일 드로어·언어스위처)·`Footer`·`CookieConsent`(동의 게이팅)·`SkipLink`·`Container`·`SectionHeading`·`PlaceholderImage`·`DownloadCTABand`·`StoreBadge`·`LegalContent`
- lib: `seo.ts`(canonical/hreflang/og, en noindex)·`analytics.ts`(GA4/Hotjar 동의·env 게이팅)·`inquiries.ts`(제출 stub — 단일 스왑 포인트)
- 페이지(각 ko/en): 홈·이용방법·요금제·문의(FAQ+폼) / download·about·privacy·terms·blog(+[slug]) / `[locale]/not-found`(404)
- SEO 인프라: `src/app/sitemap.ts`(ko만)·`src/app/robots.ts`(en disallow)
- i18n: `messages/{ko,en}.json` 15개 네임스페이스, 콘텐츠 전부 더미
- env: `apps/web/.env.example`

## 검증 (Verification)

- `pnpm --filter @helpbee/ui test` → 12 passed, `type-check` clean
- `pnpm --filter @helpbee/web build` → **25 정적 페이지 SSG green**(전 라우트 × ko/en + sitemap/robots)
- Playwright 데스크톱(1440) 시각 검증: 홈·요금제·문의 3페이지가 Figma 시안과 정합(꿀색·S-Core Dream·레이아웃 일치)
- 알려진 제약:
  - **AI 추론·이메일 인증·recommendations 미동작**(백엔드 §10) → 본 웹은 마케팅 전용이라 무관
  - **문의 폼 제출 비활성**: 백엔드 `POST /v1/inquiries` 미구현 → `lib/inquiries.ts`가 "준비 중" 반환
  - 콘텐츠·이미지·가격·법적 본문 **전부 더미** placeholder
  - 모노레포에 zod3(web)·zod4(api) 공존 → ContactForm resolver 타입 1곳 단언 우회(런타임 정상)

## 후속 작업 (Follow-up)

- 더미 → 실제 콘텐츠/이미지(next/image)·가격·법무 검토본 교체
- 백엔드 `/inquiries` 라우트 추가 후 `lib/inquiries.ts` 한 줄 연결
- 블로그 MDX/contentlayer 도입(현재는 더미 데이터 골격)
- `apps/web/CLAUDE.md` §6 · `packages/ui/CLAUDE.md` §5 **토큰 표를 Figma 기준(#E49A03 / bee-black #2D1E00 / S-Core Dream)으로 정정** — 현재 코드(@helpbee/ui preset)가 권위 소스
- GA4/Hotjar 실계정 연결, en 번역 본문, favicon/OG 이미지, Storybook + Chromatic
- apps/admin도 `@helpbee/ui` preset/프리미티브 소비(현재 미연결)

## 참조

- 설계: [docs/superpowers/specs/2026-06-17-web-frontend-mvp-design.md](../superpowers/specs/2026-06-17-web-frontend-mvp-design.md)
- 계획: [docs/superpowers/plans/2026-06-17-web-ui-foundation.md](../superpowers/plans/2026-06-17-web-ui-foundation.md)
- 디자인 핸드오프: [docs/06-design-handoff/2026-06-09-web-mvp.md](../06-design-handoff/2026-06-09-web-mvp.md)
- 권위 가이드: [apps/web/CLAUDE.md](../../apps/web/CLAUDE.md) · [packages/ui/CLAUDE.md](../../packages/ui/CLAUDE.md)
- API 계약: [docs/01-development/frontend-api-integration.md](../01-development/frontend-api-integration.md)
