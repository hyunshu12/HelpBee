# HelpBee 웹 프론트엔드 (apps/web) MVP — 설계 문서

> 작성일 2026-06-17 · 브랜치 `feature/web-frontend-mvp` · 범위 마케팅/콘텐츠 웹사이트(Phase 1)
> 근거: Figma 시안(채널 9vfusqry, 데스크톱 4프레임) + `docs/06-design-handoff/2026-06-09-web-mvp.md` + `apps/web/CLAUDE.md` + `packages/ui/CLAUDE.md`

---

## 0. 한 줄 요약

방금 완성된 **Figma 데스크톱 시안 4페이지를 진실의 원천**으로 삼아, 거의 비어있는 `apps/web` + `packages/ui`를 바닥부터 구축한다. 토큰/폰트/색상은 시안 그대로, 반응형으로 구현, 콘텐츠는 전부 더미, 다국어는 ko 우선 + en 골격(noindex), 문의폼은 UI만(제출 비활성).

## 1. 현재 상태 (구현 착수 시점)

- **apps/web**: 루트 `app/layout.tsx` + `app/page.tsx`에 `<h1>HelpBee</h1>` 스텁만. `next-intl`·`tailwind`·`react-hook-form`·`zod`·`contentlayer` 미설치. 폰트 없음. `src/app/[locale]/*`는 `.gitkeep`뿐. `next.config.js`에 `transpilePackages:['@helpbee/ui','@helpbee/types']`만 존재.
- **packages/ui**: `index.ts`가 `UI_VERSION`만 export. 토큰·컴포넌트·preset 전무. `cva`/`clsx`/`tailwind-merge` 의존성만 준비. `exports` 필드·`./tailwind.preset` 경로 없음. Radix 의존성 없음.
- **apps/admin**: 아직 `@helpbee/ui`를 import하지 않음 → **지금 ui 토큰을 정해도 admin이 깨지지 않음(블래스트 반경 0)**.
- **폰트 자산**: 레포 어디에도 S-Core Dream / Jua / Pretendard woff2 없음.

## 2. 확정된 결정 (사용자 승인)

| 항목 | 결정 |
|---|---|
| 디자인 토큰 | **Figma 시안 그대로** — 본문 S-Core Dream, 로고 Jua, 메인 `#E49A03`, 텍스트 `#2D1E00` |
| 범위 | Figma 4페이지 + **법적/SEO 전부** (download·about·privacy·terms·blog 골격·sitemap·robots·쿠키동의·404) |
| 문의폼 | react-hook-form+zod 검증 + 개인정보 동의까지 완성, **제출은 비활성**(백엔드 `/inquiries` 미구현) |
| 반응형 | **구현** (모바일 우선, 데스크톱 lg/xl에서 시안 매칭) |
| 콘텐츠 | **전부 더미/placeholder** (가격·기능·통계·법적 본문·이미지 모두 더미) |
| 폰트 | 무료 배포본 **self-host** (S-Core Dream 무료배포, Jua=구글폰트 OFL) via `next/font/local` |
| 다국어 | next-intl, **ko 기본 + en 골격(noindex + sitemap 제외)** |
| 컴포넌트 배치 | **구조 B** — ui=공유 프리미티브 / web=도메인 복합 |

## 3. 아키텍처

```
packages/ui (공유 디자인 시스템)
 ├─ src/tokens/tailwind.preset.ts   ← Figma 팔레트·폰트변수·radius 단일 소스
 ├─ src/tokens/colors.ts, typography.ts
 ├─ src/components/                 ← Button, Card, Input, Textarea, Badge,
 │                                    Accordion, Checkbox, Select, Skeleton
 ├─ src/utils/cn.ts                 ← clsx + tailwind-merge
 ├─ src/index.ts                    ← named export 배럴
 ├─ package.json                    ← exports에 '.' + './tailwind.preset' 추가
 └─ .storybook/                     ← (선택) 스토리
        ↑ transpilePackages + preset 상속
apps/web (Next.js 14 App Router)
 ├─ src/app/[locale]/
 │   ├─ layout.tsx                  ← Header + Footer + CookieConsent + 폰트 변수
 │   ├─ page.tsx                    ← 홈/랜딩 (Frame1)
 │   ├─ how-it-works/page.tsx       ← 이용 방법 (Frame2)
 │   ├─ pricing/page.tsx            ← 요금제 (Frame5)
 │   ├─ contact/page.tsx            ← 문의/FAQ (Frame3)
 │   ├─ download/page.tsx           ← 앱 다운로드 (스토어 배지 더미)
 │   ├─ about/ privacy/ terms/      ← 더미 본문
 │   ├─ blog/page.tsx + blog/[slug] ← MDX 골격 + 더미 글 1
 │   └─ [...not-found]/             ← 404
 ├─ src/components/                 ← 도메인 복합 컴포넌트 (아래 6장)
 ├─ src/lib/                        ← api 클라(문의 stub), analytics, seo 헬퍼, i18n
 ├─ src/fonts/                      ← S-Core Dream·Jua woff2
 ├─ messages/{ko,en}.json           ← 모든 카피(더미 포함)
 ├─ src/middleware.ts               ← next-intl locale 라우팅
 ├─ src/app/sitemap.ts, robots.ts   ← SEO 인프라(en noindex/제외)
 ├─ tailwind.config.ts              ← preset 상속
 └─ next.config.js                  ← next-intl 플러그인 + 기존 transpile/images
```

**구조 정리**: 충돌하는 루트 `app/` 스텁(layout.tsx·page.tsx)은 제거하고 `src/app/[locale]`로 일원화한다. (Next.js는 `src/app`을 앱 루트로 인식)

### 의존 방향
- `apps/web` → `@helpbee/ui`(프리미티브+토큰) → 단방향. ui는 비즈니스 로직/데이터 페칭 없음.
- web 도메인 복합 컴포넌트는 ui 프리미티브를 조합. features 간 직접 결합 없음.
- 폰트는 app-level self-host. ui preset은 `var(--font-sans)`/`var(--font-logo)` 변수만 참조(폰트 파일은 app이 주입).

## 4. 디자인 토큰 (Figma 추출)

### honey 팔레트 (앵커: `#E49A03` = honey-500)
시안에서 관찰된 값을 흡수해 50~900 스케일 생성. 대표 값(정확한 중간 보간은 구현 시 확정):
- `honey-50` ≈ `#FFFBF0` / `honey-100` ≈ `#FFEDC7` / `honey-200` ≈ `#FBE3A8`
- `honey-300` ≈ `#F7C863` / `honey-400` ≈ `#F0B23B` / **`honey-500` = `#E49A03`(primary)**
- `honey-600` ≈ `#C2850A` / `honey-700` ≈ `#9B6A08` / `honey-800` ≈ `#74500A` / `honey-900` ≈ `#4D360A`
- 시안 보조 배경: `#FFEECB`(TIP 박스), `#FCF5E0`(혜택 pill), `#F9EBD0`(비교표 행), `#FFF1CE`/`#FFE3AB`(그라데이션), `#E4D3B9`(푸터), `#E9AB2B`.

### 시맨틱 / 텍스트
- `bee-black` = `#2D1E00`(제목/강조), 본문 보조 `#000000`(+투명도), placeholder `#AFAFAF`.
- `success`/`warning`/`danger`는 ui CLAUDE.md 시맨틱 유지(앱 진단 tier와 별개, 마케팅 웹에선 최소 사용).

### 폰트
- `--font-sans` = **S-Core Dream** (본문·헤딩. 시안에서 weight 200/400/500/600/700/800 사용 → 필요한 굵기 woff2 서브셋).
- `--font-logo` = **Jua** (로고 "HelpBee").
- preset의 `fontFamily.sans`/`.logo`가 위 변수 참조.

### radius / 기타
- pill 버튼 = `rounded-full`, 카드 = `rounded-2xl`(시안 38~44px), 입력 = `rounded-xl`.
- 본문 18px+ 기조(장년층) 유지하되 시안 폰트 크기(20~64px) 우선 매핑.

> **문서 정정 포함**: 본 결정에 맞춰 `packages/ui/CLAUDE.md`·`apps/web/CLAUDE.md` 토큰 표를 Figma 기준(`#E49A03`, `bee-black #2D1E00`, S-Core Dream)으로 갱신한다. (기존 문서의 bee-black `#6B4423` vs `#2A1F0E` 충돌도 이때 해소)

## 5. 라우트 ↔ Figma 매핑

| route | Figma | 핵심 섹션 |
|---|---|---|
| `/[locale]` | Frame1 (55:3) | 히어로("AI가 지키는 벌통 건강"+무료시작 CTA) → 소개 3카드(AI진단/즉각대응/데이터보안) → 주요기능 4(정밀질병/해충/여왕벌/맞춤조언) → 추천대상 3(초보/전문/조합) → 통계(95%·10,000+·24/7) → CTA 밴드 |
| `/how-it-works` | Frame2 (55:113) | 3단계(01 촬영+TIP / 02 분석 30초 / 03 결과) → CTA 밴드 |
| `/pricing` | Frame5 (55:278) | 플랜 3(베이직/프로[추천 배지]/엔터프라이즈) → 상세 기능 비교표 → 모든 플랜 공통 혜택 → CTA 밴드 |
| `/contact` | Frame3 (55:188) | FAQ 검색 + 아코디언(5) + "전체 FAQ" / 문의채널 3(실시간채팅·이메일·전화) + **문의폼**(이름·이메일·문의유형·내용·동의) |
| `/download` | 헤더·CTA 타깃 | 스토어 배지(App Store/Play, 더미 링크 + UTM) |
| `/about` | 푸터 | 더미 회사 소개 |
| `/privacy` `/terms` | 푸터·문의 동의 | 더미 법적 본문(섹션 골격) |
| `/blog` `/blog/[slug]` | 푸터 | MDX 목록 + 더미 글 1(Article 골격) |
| `sitemap.xml` `robots.txt` | SEO | 자동 생성, en `noindex`/sitemap 제외 |
| `[...not-found]` | 글로벌 | 404(홈·블로그 복귀) |

전 페이지 공통: **sticky 헤더**(로고 + 서비스소개/이용방법/요금제/문의하기 nav + 다운로드 버튼 + 언어스위처) · **푸터**(Service/Support/Company/Contact 4열 + copyright) · **쿠키 동의 배너**.

> 네비 "서비스 소개" = 홈(`/`). 시안 nav는 서비스소개/이용방법/요금제/문의하기 4개.

## 6. 컴포넌트 인벤토리

### packages/ui (프리미티브, shadcn 패턴 — cva+forwardRef+cn)
`Button`(filled-pill/outline-pill/white-pill/ghost), `Card`, `Input`, `Textarea`, `Badge`("추천" 등), `Accordion`(FAQ), `Checkbox`(동의), `Select`(문의 유형), `Skeleton`.
- Radix 도입: `Accordion`/`Select`/`Checkbox`에 `@radix-ui/react-*` 추가(접근성). Button 등 단순 프리미티브는 무의존.

### apps/web/src/components (도메인 복합)
- 글로벌: `Header`, `Footer`, `CookieConsent`, `LanguageSwitcher`, `SkipLink`, `DownloadCTABand`(반복 하단 CTA), `StoreBadge`.
- 홈: `Hero`, `IntroCard`, `FeatureCard`, `RecommendCard`, `StatsBlock`, `QuoteBlock`.
- 이용방법: `StepCard`(번호+화면+설명), `TipBox`.
- 요금제: `PricingCard`, `PricingCompareTable`, `BenefitPills`.
- 문의/FAQ: `FaqSearch`, `FaqList`(Accordion 사용), `ContactChannelCard`, `ContactForm`.
- 블로그: `mdx/*` 컴포넌트, `PostCard`.

## 7. 횡단 정책

- **i18n**: next-intl, `defaultLocale=ko`, `locales=['ko','en']`. en은 빈 스켈레톤 + `robots noindex` + sitemap 제외. 모든 노출 문자열은 `messages/{locale}.json` 키(더미 카피 포함).
- **문의폼**: `src/lib/inquiries.ts`에 `submitInquiry()` 단일 함수 — 현재는 "준비 중" 반환(제출 비활성, 토스트/안내). 백엔드 `/inquiries` 생기면 이 함수 1곳만 교체. 폼 자체는 react-hook-form+zod로 완전 검증, 개인정보 동의 체크 필수.
- **반응형**: Tailwind 모바일 우선. 데스크톱(1512px 시안)은 `lg`/`xl`에서 매칭. 헤더는 모바일 드로어(+포커스 트랩), 터치 타깃 48px+.
- **SEO**: 페이지별 `generateMetadata`(title/desc/OG/canonical/`alternates.languages` hreflang) 공통 헬퍼 `src/lib/seo.ts`. 블로그 글 Article JSON-LD(골격).
- **분석**: GA4/Hotjar는 `NEXT_PUBLIC_GA_ID`/`NEXT_PUBLIC_HOTJAR_ID` env + **쿠키 동의 후에만** 로드. env 미설정 시 자동 미로드(로컬·더미 안전).
- **접근성**: 이미지 alt(더미여도), 색대비 AA(꿀색 배경 위 bee-black), 키보드 내비, Skip-link.

## 8. 환경 변수 (`.env.example` 추가)
```
NEXT_PUBLIC_API_URL=http://localhost:3001
NEXT_PUBLIC_GA_ID=            # 비면 미로드
NEXT_PUBLIC_HOTJAR_ID=        # 비면 미로드
NEXT_PUBLIC_APP_STORE_URL=    # 더미 가능
NEXT_PUBLIC_PLAY_STORE_URL=   # 더미 가능
```

## 9. 구현 단계 (의존성 순)

1. **ui 토큰 + preset** — colors/typography/tailwind.preset.ts, package.json `exports`(`./tailwind.preset`), cn 유틸.
2. **ui 프리미티브** — Button·Card·Input·Textarea·Badge·Accordion·Checkbox·Select·Skeleton + index 배럴. (Radix 의존 추가)
3. **web 스캐폴드** — 패키지 설치(next-intl, react-hook-form, zod, contentlayer 등), tailwind.config(preset 상속), 폰트 self-host, middleware, `src/app/[locale]/layout.tsx`(폰트 변수), Header/Footer/CookieConsent, 루트 `app/` 스텁 제거.
4. **Figma 4페이지** — 홈 → 이용방법 → 요금제 → 문의/FAQ (각 도메인 복합 컴포넌트 포함).
5. **법적/SEO 전부** — download·about·privacy·terms·blog(MDX 골격+더미글)·sitemap·robots·404.
6. **마감** — 반응형 다듬기, 접근성/Lighthouse 점검, CLAUDE.md 토큰 표 정정, `pnpm --filter web lint/typecheck/build`.

## 10. 검증 (완료 기준)

- `pnpm --filter @helpbee/ui typecheck/build` 통과, 프리미티브 렌더.
- `pnpm --filter web lint && typecheck && build` 통과.
- 4페이지가 데스크톱에서 시안과 시각적으로 일치(폰트·색·레이아웃), 모바일에서 깨짐 없음.
- 문의폼 검증 동작(필수/형식/동의), 제출 시 "준비 중" 안내.
- `sitemap.xml`/`robots.txt` 생성, en noindex.
- 브랜치 보호 준수(feature → develop PR).

## 11. 범위 밖 (이번 작업 제외)

- 실제 콘텐츠/카피/가격/법적 문구(전부 더미) · 실제 이미지 자산 · 데모 영상.
- 백엔드 `/inquiries` 라우트 구현(클라 stub만).
- 영어 본문 번역(en은 골격/noindex).
- GA4/Hotjar 실 계정 연결(env 자리만).
- admin/모바일 영향 없음.

## 12. 미해결 / 추후

- S-Core Dream 무료 배포본 **다운로드 출처 확정** 후 self-host(라이선스 확인).
- 더미 → 실제 콘텐츠 교체 시점(가격/법무/이미지).
- 쿠키 동의 저장소·재동의 주기 세부(기본: localStorage + GA4/Hotjar 개별 토글).
- 블로그 contentlayer vs 대체(현 Next 14 호환성) — 구현 단계에서 최종 확정.
