# packages/ui — HelpBee Shared Design System

> 이 문서는 `@helpbee/ui` 워크스페이스 전용 가이드다. 루트 `CLAUDE.md`와 함께 읽는다.

---

## 1. 목적 (Purpose)

`apps/admin`(운영 대시보드)과 `apps/web`(마케팅/콘텐츠 사이트)이 **공유하는 디자인 시스템**.

다음을 한 곳에서 관리한다:

- **재사용 가능한 React 컴포넌트** — Button, Card, Dialog, Table, Badge, Input, Tabs, Skeleton
- **디자인 토큰** — 꿀색 팔레트, 타이포 스케일, radius, shadow, 모션
- **Tailwind preset** — 두 앱이 동일한 토큰을 자동 상속
- **유틸리티** — `cn()` (clsx + tailwind-merge), variant helper

**비목표(Non-goals)**:

- 비즈니스 로직 (admin/web 각자 책임)
- 데이터 페칭 (TanStack Query는 각 앱이 직접)
- 복잡한 도메인 위젯 (BboxOverlay 같은 건 admin 전용)

---

## 2. 기술 스택 (Tech Stack)

| 영역             | 선택                                                          |
| ---------------- | ------------------------------------------------------------- |
| 런타임           | **React 18** + **TypeScript (strict)**                        |
| 스타일           | **Tailwind CSS** (preset 노출) + CSS 변수 토큰                |
| 컴포넌트 패턴    | **shadcn/ui** 패턴 (Radix Primitives 기반, 코드 owned)        |
| Variant          | **class-variance-authority (cva)**                            |
| className 합성   | **clsx** + **tailwind-merge** → `cn()` helper                 |
| Primitives       | **@radix-ui/react-***  (Dialog, Tabs, Tooltip 등)            |
| 아이콘           | **lucide-react** (peer dep)                                   |
| 빌드             | **tsup** 또는 Next 내부 transpile (`transpilePackages`)       |
| 시각 회귀        | **Storybook** + **Chromatic**                                 |

> **금지**: MUI, Chakra, Mantine 등 완성형 컴포넌트 라이브러리. shadcn 패턴 유지.

---

## 3. 폴더 구조 (Folder Structure)

```
packages/ui/
├── CLAUDE.md
├── package.json
├── src/
│   ├── index.ts              # 모든 public export 한 곳에 모음 (existing)
│   ├── components/           # Button.tsx, Card.tsx, Dialog.tsx ...
│   ├── tokens/               # tailwind.preset.ts, colors.ts, typography.ts
│   └── utils/                # cn.ts (clsx + tailwind-merge)
└── .storybook/               # Storybook 설정 + *.stories.tsx
```

### `src/index.ts` 규칙

- 모든 컴포넌트/토큰/유틸은 여기서 named export
- deep import 금지 — `import { Button } from '@helpbee/ui'` 만 허용
- `tailwind.preset`은 `@helpbee/ui/tailwind.preset` 별도 export (Tailwind config가 require)

---

## 4. 컴포넌트 목록 (Components)

Phase 1 출시에 필요한 최소 세트(shadcn 표준 패턴):

| 컴포넌트     | 용도                                              | 의존 Radix             |
| ------------ | ------------------------------------------------- | ---------------------- |
| **Button**   | primary/secondary/ghost/destructive variant       | (slot)                 |
| **Card**     | KPI 카드, 콘텐츠 그룹                             | -                      |
| **Table**    | 기본 마크업 (admin은 TanStack Table로 래핑)       | -                      |
| **Dialog**   | 확인/삭제/편집 모달                               | @radix-ui/react-dialog |
| **Badge**    | 상태(active/blocked/pending), 카테고리 태그       | -                      |
| **Input**    | 텍스트/이메일/숫자 — react-hook-form `register` 호환 | -                  |
| **Tabs**     | 탭 네비게이션                                     | @radix-ui/react-tabs   |
| **Skeleton** | 로딩 placeholder                                  | -                      |

### 추후 추가 후보

`Tooltip`, `DropdownMenu`, `Toast`, `Select`, `Checkbox`, `Switch`, `Avatar`, `Sheet` — 필요 발생 시 PR로 추가.

### 컴포넌트 작성 규칙

- 파일: `src/components/{Name}.tsx` (PascalCase)
- export: `index.ts`에 re-export
- variant는 cva, prop은 `forwardRef` + 표준 HTML 속성 spread 가능
- 접근성: Radix가 제공하는 ARIA를 끄지 말 것
- className은 항상 `cn(base, variants, className)` 마지막 prop이 override

---

## 5. 토큰 (Design Tokens)

### `src/tokens/tailwind.preset.ts`

두 앱의 `tailwind.config.ts`가 import하는 **단일 진실 소스**.

#### 색상 팔레트

```
honey-50   #FFFBF0    배경 베이스 (web)
honey-100  #FEF3D6
honey-200  #FCE7AD
honey-300  #FAD984
honey-400  #F8CB5C
honey-500  #F5B82E    primary (브랜드)
honey-600  #DBA226
honey-700  #B0811E
honey-800  #856116
honey-900  #5A410F

bee-black  #2A1F0E    제목/강조 텍스트
bee-brown  #6B4423    보조 텍스트
```

추가 시맨틱 색:

- `success` (꿀벌 친화 그린), `warning` (꿀색 경고), `danger` (낭충봉아부패병 경고용 레드)

#### 타이포 스케일

- `text-xs` 12 / `sm` 14 / `base` 16 / `lg` 18 / `xl` 20 / `2xl` 24 / `3xl` 30 / `4xl` 36 / `5xl` 48
- 본문 기본은 **`lg` (18px)** — apps/web의 양봉가 가독성 요구

#### Radius / Shadow / Motion

- radius: `sm` 6 / `md` 10 / `lg` 14 / `xl` 18 / **`2xl` 24 (기본)**
- shadow: `sm` / `md` / `lg` — soft, 약한 꿀색 틴트(rgba 기반)
- motion: `duration-150 ease-out` 표준

---

## 6. 두 앱이 사용하는 방식 (Consumer Setup)

### `apps/admin/tailwind.config.ts` 와 `apps/web/tailwind.config.ts`

```ts
import type { Config } from 'tailwindcss';

const config: Config = {
  presets: [require('@helpbee/ui/tailwind.preset')],
  content: [
    './src/**/*.{ts,tsx,mdx}',
    '../../packages/ui/src/**/*.{ts,tsx}',
  ],
};

export default config;
```

### Next.js 트랜스파일

`apps/admin/next.config.js` / `apps/web/next.config.js`:

```js
module.exports = {
  transpilePackages: ['@helpbee/ui'],
};
```

`@helpbee/ui`는 별도 빌드 없이 Next가 직접 트랜스파일 → 빠른 dev/HMR.

### `package.json` 의존

- 두 앱은 `"@helpbee/ui": "workspace:*"`로 의존 선언
- ui는 `react`, `react-dom`을 **peerDependency**로만 선언 (중복 설치 방지)

---

## 7. Storybook + 시각 회귀 (Visual Regression)

### `.storybook/`

- `main.ts` — `stories: ['../src/**/*.stories.tsx']`, `addons: ['@storybook/addon-essentials']`
- `preview.tsx` — 글로벌 Tailwind import + 꿀색 배경 옵션
- 각 컴포넌트는 `Button.stories.tsx`처럼 동일 폴더 또는 `stories/` 분리

### Chromatic

- main 브랜치 머지 시 자동 publish (CI에서 `chromatic --project-token=$CHROMATIC_TOKEN`)
- 시각 diff 발생 시 PR에 코멘트 — 의도된 변경이면 reviewer가 approve

### 로컬 실행

```bash
pnpm --filter @helpbee/ui storybook    # http://localhost:6006
```

---

## 8. AI 작업 가이드라인 (AI Coding Rules)

### MUST

1. **새 컴포넌트는 `src/components/{Name}.tsx`** + `index.ts` re-export
2. **shadcn 패턴 유지** — Radix Primitive + cva variant + forwardRef + cn 합성
3. **토큰은 `tokens/tailwind.preset.ts` 한 곳**에서만 정의 — 컴포넌트 안에서 hex 하드코딩 금지
4. 토큰(색/스페이싱/radius) 변경 PR은 **두 앱 모두 영향** — PR 설명에 영향도와 스크린샷 명시
5. 컴포넌트 추가 시 **Storybook 스토리 1개 이상** 작성 (default + 주요 variant)
6. 접근성 — Radix 제공 ARIA/keyboard 핸들러 끄지 말 것, alt/label 필수
7. peer dep(`react`, `lucide-react`)은 buyer 앱에서 설치된 버전을 따른다
8. 파일 삭제는 **`trash`** 사용

### MUST NOT

- ❌ 비즈니스 로직, 데이터 페칭, API 호출
- ❌ admin/web 둘 중 하나에만 의미 있는 컴포넌트 (그건 해당 앱 내부 components/에)
- ❌ MUI/Chakra/Mantine 등 외부 컴포넌트 라이브러리 의존
- ❌ deep import(`@helpbee/ui/components/Button`) 강제 — `index.ts` 경유
- ❌ 색상/스페이싱 hex/px 하드코딩
- ❌ 기존 컴포넌트 prop의 breaking change (꼭 필요하면 deprecate → 다음 메이저)

### Decision Log

색 팔레트, 타이포 스케일, radius 변경 같은 굵직한 변경은 본 문서를 ADR 식으로 갱신.

---

## 9. 체크리스트 (PR Checklist)

- [ ] 새 컴포넌트는 `src/components/{Name}.tsx` + `index.ts` export
- [ ] cva variant 정의 (variant/size 등 표준 prop)
- [ ] forwardRef + HTML 속성 spread 지원
- [ ] `cn(...)` 마지막에 className override 가능
- [ ] Storybook 스토리 추가 (default + 주요 variant)
- [ ] 접근성 — Radix Primitive 사용, 키보드 동작 정상
- [ ] hex/px 하드코딩 없음, 토큰 사용
- [ ] 토큰 변경이면 PR 설명에 admin/web 영향도 + 스크린샷
- [ ] `pnpm --filter @helpbee/ui lint / typecheck / build` 통과
- [ ] Chromatic 시각 diff 검토 (의도된 변경만 approve)
- [ ] react/react-dom은 peerDependency, dependencies로 옮기지 않았다
