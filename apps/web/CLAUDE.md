# apps/web — HelpBee Marketing & Content Site

> 이 문서는 `apps/web` 워크스페이스 전용 가이드다. 루트 `CLAUDE.md`와 함께 읽는다.

---

## 1. 목적 (Purpose)

양봉가가 **5분 안에** 다음 두 가지를 할 수 있게 만든다:

1. HelpBee가 무엇이고 어떤 가치를 주는지 이해 ("응애·낭충봉아부패병을 휴대폰 카메라로 진단")
2. 모바일 앱 다운로드(App Store / Play Store) 또는 문의

추가로:

- 콘텐츠 마케팅 — 양봉 관련 블로그(MDX)로 SEO 유입
- 가격(Pricing), 회사 소개(About), 개인정보처리방침/이용약관 등 정적 페이지 호스팅
- 문의 폼 → `apps/api`의 `/inquiries` 엔드포인트로 전송

**비목표(Non-goals)**: 진단 기능 자체, 사용자 로그인, 결제 — 모두 모바일 앱이 담당.

---

## 2. 기술 스택 (Tech Stack)

| 영역          | 선택                                                         |
| ------------- | ------------------------------------------------------------ |
| Framework     | **Next.js 14 (App Router)** + **TypeScript (strict)**        |
| 스타일링      | **Tailwind CSS** + `@helpbee/ui`                             |
| 다국어        | **next-intl** (middleware 기반 locale 라우팅)                |
| SEO           | **next-seo** + Next 내장 metadata API + `next/og`            |
| 콘텐츠        | **MDX** + **contentlayer** (블로그용)                        |
| 분석          | **GA4** + **Hotjar** (production만, afterInteractive)        |
| 폼            | **react-hook-form** + **zod** → `apps/api` `/inquiries`      |
| 폰트          | **Pretendard** (next/font/local 또는 self-host)              |
| 이미지        | **next/image** + AVIF/WebP                                   |

> **금지**: 별도 CMS(Sanity, Contentful) — Phase 1은 MDX 자체관리. 마이그레이션 필요 시 별도 ADR.

---

## 3. 폴더 구조 (Folder Structure)

```
apps/web/
├── CLAUDE.md
├── next.config.js
├── package.json
├── tsconfig.json
├── src/
│   ├── app/
│   │   └── [locale]/                  # next-intl: /ko, /en
│   │       ├── how-it-works/          # /[locale]/how-it-works (작동 원리)
│   │       ├── pricing/               # /[locale]/pricing
│   │       ├── about/                 # /[locale]/about
│   │       ├── blog/                  # /[locale]/blog (목록 + [slug])
│   │       ├── contact/               # /[locale]/contact (문의 폼)
│   │       ├── download/              # /[locale]/download (앱스토어/플스토어)
│   │       ├── privacy/               # /[locale]/privacy
│   │       └── terms/                 # /[locale]/terms
│   └── lib/                           # contentlayer config, analytics, api 클라
├── content/
│   └── blog/                          # *.mdx (frontmatter 포함)
└── messages/                          # next-intl 번역 (ko.json, en.json)
```

### `[locale]` 라우팅

- 모든 페이지는 `app/[locale]/` 아래에 배치
- next-intl middleware가 root `/` 요청을 사용자 Accept-Language에 따라 `/ko` 또는 `/en`으로 리다이렉트
- 정적 빌드 시 `generateStaticParams`로 두 locale 모두 prerender

---

## 4. i18n (다국어)

| 언어       | 상태             | 비고                                               |
| ---------- | ---------------- | -------------------------------------------------- |
| **ko** (기본) | Phase 1 출시     | 모든 텍스트는 `messages/ko.json` 키로 관리         |
| **en**       | Phase 2 (선택)   | 해외 양봉가 문의 발생 시 활성화                    |

### 규칙

- **하드코딩 금지** — 모든 사용자 노출 문자열은 `messages/{locale}.json` 키 사용
- 컴포넌트에서 `useTranslations()` 훅 (클라) 또는 `getTranslations()` (서버) 사용
- 날짜/숫자는 `next-intl/server`의 `getFormatter()`
- middleware: `src/middleware.ts`에서 `createMiddleware({ locales: ['ko', 'en'], defaultLocale: 'ko' })`

---

## 5. SEO

### 필수 산출물

- `app/sitemap.ts` — 모든 정적 페이지 + MDX 블로그 슬러그 자동 수집
- `app/robots.ts` — production은 allow, preview는 disallow
- 페이지별 `generateMetadata()` — title/description/OG/canonical
- **OG 이미지**: `app/[locale]/.../opengraph-image.tsx` (next/og 동적 생성, 꿀색 배경 + 제목)
- 구조화 데이터 — 블로그 글에 `Article` JSON-LD

### 키워드 전략

- **양봉**, **꿀벌 응애**, **꿀벌 진단**, **낭충봉아부패병**, **AI 양봉**, **스마트 양봉**
- 블로그 제목/메타에 자연스럽게 포함, 키워드 스터핑 금지

### Lighthouse 목표

- Performance ≥ **90**
- SEO ≥ **95**
- Accessibility ≥ **90**
- Best Practices ≥ **95**

---

## 6. 디자인 톤 (Design Tone)

**브랜드 정체성**: 양봉의 자연스러움 + 기술의 신뢰감.

| 요소         | 가이드                                                       |
| ------------ | ------------------------------------------------------------ |
| 메인 색상    | **꿀색 #F5B82E** (`honey-500`), **흙갈색 #6B4423** (`bee-black`) |
| 배경         | 따뜻한 화이트 `honey-50` (#FFFBF0) — 차가운 그레이 금지       |
| 타이포       | **Pretendard** — 제목 700, 본문 400/500                      |
| 본문 크기    | **18px 이상** (양봉가는 50대 이상 다수 — 가독성 최우선)      |
| 행간         | 1.6 이상                                                     |
| 일러스트     | 자연 스타일 (꿀벌, 벌집, 들꽃) — Lucide 아이콘은 보조용      |
| 모서리       | `rounded-2xl` 기본, 크게                                     |

**금지**: 차가운 SaaS 톤(블루+그레이), 작은 폰트, 빽빽한 정보 밀도.

---

## 7. 분석 (Analytics)

### GA4

- `NEXT_PUBLIC_GA_ID` 환경변수
- `app/[locale]/layout.tsx` 또는 root `layout.tsx`에서 `<Script strategy="afterInteractive" />`
- production 빌드에서만 로드 (`process.env.NODE_ENV === 'production'` 체크)
- 핵심 이벤트: `cta_download_click`, `cta_contact_submit`, `blog_read_complete`

### Hotjar

- `NEXT_PUBLIC_HOTJAR_ID` 환경변수
- 동일하게 afterInteractive
- 쿠키 동의 배너 — 한국 PIPA 기준 선택 동의 필요(GDPR보다 약함이지만 안전)

### 환경변수 정리

```bash
NEXT_PUBLIC_API_URL=http://localhost:4000
NEXT_PUBLIC_GA_ID=G-XXXXXXXXXX
NEXT_PUBLIC_HOTJAR_ID=1234567
NEXT_PUBLIC_APP_STORE_URL=https://apps.apple.com/app/...
NEXT_PUBLIC_PLAY_STORE_URL=https://play.google.com/store/apps/...
```

---

## 8. 콘텐츠 (Content / Blog)

### 위치

- `content/blog/*.mdx`
- contentlayer가 빌드 시 타입 안전한 모델로 변환

### Frontmatter 스펙

```yaml
---
title: "꿀벌 응애, 카메라로 진단하는 시대"
description: "..."
date: 2026-05-01
author: 김양봉
coverImage: /images/blog/varroa-cover.jpg
locale: ko        # ko | en
tags: [응애, AI진단]
draft: false
---
```

### 작성 규칙

- 모든 새 글은 `locale` 명시 — 다국어 분리
- `draft: true`는 production 빌드에서 제외
- 이미지는 `public/images/blog/` 아래, next/image로 렌더
- MDX 컴포넌트(Callout, Figure 등)는 `@helpbee/ui` 또는 `src/components/mdx/`

---

## 9. 로컬 개발 (Local Development)

```bash
pnpm install
pnpm --filter web dev    # http://localhost:3000
```

### 포트 약속

- **`apps/web` → 3000 (기본)**
- `apps/admin` → 3001
- `apps/api` → 4000

### `.env.local` 최소

```bash
NEXT_PUBLIC_API_URL=http://localhost:4000
NEXT_PUBLIC_APP_STORE_URL=https://...
NEXT_PUBLIC_PLAY_STORE_URL=https://...
```

GA/Hotjar는 로컬에서는 비활성화(없어도 OK).

---

## 10. 검증 (Validation)

### 빌드 전 체크

```bash
pnpm --filter web lint
pnpm --filter web typecheck
pnpm --filter web build
```

### Lighthouse

- 주요 페이지(`/`, `/how-it-works`, `/pricing`, `/blog/[slug]`)에서 모바일 + 데스크톱 모두 측정
- 90+ 미달 시 PR 머지 보류

### 접근성

- 모든 이미지 `alt` 필수
- 색상 대비 WCAG AA (꿀색 배경 위 텍스트는 진한 brown 사용)
- 키보드 네비게이션 (Tab으로 모든 CTA 도달 가능)

---

## 11. 배포 (Deployment)

- **Vercel** — `apps/web` 워크스페이스를 monorepo project로 등록
- 도메인: production `helpbee.kr` (가칭), preview는 `*.vercel.app`
- ISR 또는 SSG — 정적 페이지는 `export const dynamic = 'force-static'`
- 블로그는 빌드 시 정적 생성 (`generateStaticParams`)
- production env에 GA/Hotjar/store url 등록

---

## 12. AI 작업 가이드라인 (AI Coding Rules)

### MUST

1. **새 페이지는 반드시 `app/[locale]/` 안**에 만든다 — locale 없이 라우팅 추가 금지
2. **모든 사용자 노출 문자열은 `messages/{locale}.json`** 키 사용 (하드코딩 금지)
3. UI 빌딩블록은 **`@helpbee/ui` 우선**, 없으면 ui 패키지에 추가 후 사용
4. 폼 제출은 **`apps/api` `/inquiries`** 엔드포인트로 — 외부 폼 서비스(Tally, Typeform) 도입 금지
5. 이미지는 **`next/image`** + 적절한 `sizes` prop
6. 새 블로그 글은 `content/blog/*.mdx` + frontmatter 스키마 준수
7. 파일 삭제는 **`trash`** 사용 (`rm` 금지)
8. SEO metadata — 모든 페이지 `generateMetadata()` 구현

### MUST NOT

- ❌ 사용자 로그인/회원가입 추가 (모바일 앱 책임)
- ❌ 결제/구독 플로우 (모바일 앱 책임)
- ❌ Sanity/Contentful 같은 외부 CMS 도입 (Phase 1)
- ❌ 차가운 SaaS 톤(블루+그레이) — 꿀색 톤 유지
- ❌ 18px 미만 본문
- ❌ 폼 데이터를 client에서 외부 도메인으로 직접 전송 (반드시 apps/api 경유)
- ❌ Tailwind config 직접 확장 — 토큰은 `@helpbee/ui` preset에서

### Decision Log

콘텐츠 전략 / 디자인 톤 변경은 본 문서 §6, §8을 갱신하고 PR 설명에 사유를 적는다.

---

## 13. 체크리스트 (PR Checklist)

- [ ] 새 라우트는 `app/[locale]/` 아래에 있다
- [ ] 모든 노출 문자열이 `messages/ko.json`에 키로 추가됐다 (en은 Phase 2)
- [ ] `generateMetadata()` 구현 — title/description/OG
- [ ] sitemap.ts에 자동 포함되거나, 동적 라우트면 generateStaticParams
- [ ] 이미지 `next/image` 사용 + `alt` 텍스트
- [ ] 18px 이상 본문, 명도 대비 AA
- [ ] `@helpbee/ui` 컴포넌트 우선 사용
- [ ] 폼은 react-hook-form + zod, 제출은 `apps/api` 경유
- [ ] Lighthouse 모바일 ≥ 90 (수동 확인 또는 CI)
- [ ] `pnpm --filter web lint / typecheck / build` 통과
- [ ] `.env.example` 동기화 (새 env가 있다면)
