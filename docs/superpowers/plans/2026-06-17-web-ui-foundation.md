# Design System Foundation (`@helpbee/ui`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `@helpbee/ui` shared design-system foundation — Figma-derived tokens, a Tailwind preset, the `cn()` util, and core primitive components (Button, Card, Badge, Input, Textarea, Skeleton) — so `apps/web` can consume them.

**Architecture:** shadcn-style primitives (`cva` variants + `forwardRef` + `cn` class merge). Tokens live once in `src/tokens` and are exposed as a Tailwind preset at `@helpbee/ui/tailwind.preset`. Components reference token classes (e.g. `bg-honey-500`), never hardcoded hex. Fonts are injected by the app via CSS variables (`--font-sans`, `--font-logo`); the preset only references those variable names.

**Tech Stack:** React 18, TypeScript (strict), Tailwind CSS 3, class-variance-authority, clsx, tailwind-merge, Vitest + @testing-library/react (unit/smoke tests).

**Scope note:** Radix-based primitives (Accordion, Select, Checkbox) are intentionally deferred to the plan that builds the contact/FAQ page (their only consumer) to keep this plan cohesive. This plan delivers a buildable, type-checking, tested `@helpbee/ui` package.

**Reference spec:** `docs/superpowers/specs/2026-06-17-web-frontend-mvp-design.md` (§3 architecture, §4 tokens, §6 components).

**Working dir / branch:** repo root `/Users/hyeonsyu/Documents/02_Work/04_MRMR/01_HelpBee`, branch `feature/web-frontend-mvp` (already created).

---

## File Structure

| File | Responsibility |
|---|---|
| `packages/ui/package.json` | deps (cva/clsx/tailwind-merge present) + add Vitest/RTL devdeps + `exports` map (`.` + `./tailwind.preset`) + scripts |
| `packages/ui/tsconfig.json` | strict TS for React lib (verify/exists) |
| `packages/ui/vitest.config.ts` | jsdom env + react plugin + setup file |
| `packages/ui/vitest.setup.ts` | import `@testing-library/jest-dom` |
| `packages/ui/src/utils/cn.ts` | clsx+tailwind-merge class merger |
| `packages/ui/src/utils/cn.test.ts` | unit test for cn |
| `packages/ui/src/tokens/colors.ts` | honey palette + bee + surface (Figma hex) |
| `packages/ui/src/tokens/typography.ts` | fontFamily token (CSS var refs) |
| `packages/ui/src/tokens/tailwind.preset.ts` | Tailwind preset consuming colors+typography |
| `packages/ui/src/components/Button.tsx` | pill button, 4 variants × 3 sizes |
| `packages/ui/src/components/Card.tsx` | rounded container |
| `packages/ui/src/components/Badge.tsx` | small label ("추천") |
| `packages/ui/src/components/Input.tsx` | text input (RHF register compatible) |
| `packages/ui/src/components/Textarea.tsx` | multiline input |
| `packages/ui/src/components/Skeleton.tsx` | loading placeholder |
| `packages/ui/src/components/*.test.tsx` | smoke/behavior tests |
| `packages/ui/src/index.ts` | named-export barrel (replace UI_VERSION stub) |

---

## Task 0: Package setup (deps, test tooling, exports)

**Files:**
- Modify: `packages/ui/package.json`
- Verify/Create: `packages/ui/tsconfig.json`
- Create: `packages/ui/vitest.config.ts`
- Create: `packages/ui/vitest.setup.ts`

- [ ] **Step 1: Inspect current package.json**

Run: `cat packages/ui/package.json`
Expected: shows `class-variance-authority`, `clsx`, `tailwind-merge` deps; `react`/`react-dom` deps; `tailwindcss` + `typescript` devdeps; NO `exports`, NO test deps.

- [ ] **Step 2: Add exports map, scripts, and devDeps to package.json**

Edit `packages/ui/package.json` so it contains these fields (merge — keep existing `name`, `version`, existing deps). `react`/`react-dom` must be **peerDependencies** (move them out of `dependencies` if present):

```jsonc
{
  "name": "@helpbee/ui",
  "version": "0.1.0",
  "type": "module",
  "exports": {
    ".": { "types": "./src/index.ts", "default": "./src/index.ts" },
    "./tailwind.preset": { "types": "./src/tokens/tailwind.preset.ts", "default": "./src/tokens/tailwind.preset.ts" }
  },
  "scripts": {
    "lint": "eslint src --ext .ts,.tsx --max-warnings 0",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "class-variance-authority": "^0.7.0",
    "clsx": "^2.0.0",
    "tailwind-merge": "^2.2.0"
  },
  "peerDependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@testing-library/jest-dom": "^6.4.0",
    "@testing-library/react": "^15.0.0",
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "@vitejs/plugin-react": "^4.2.0",
    "jsdom": "^24.0.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "tailwindcss": "^3.3.0",
    "typescript": "^5.3.0",
    "vitest": "^1.6.0"
  }
}
```

> `react`/`react-dom` appear in BOTH peerDependencies (consumer provides) and devDependencies (so tests render in isolation). This is the standard component-library pattern.

- [ ] **Step 3: Ensure tsconfig.json exists and is strict**

Run: `cat packages/ui/tsconfig.json` — if it exists and has `"strict": true` + `"jsx": "react-jsx"`, skip to Step 4. Otherwise create it:

```jsonc
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "types": ["vitest/globals", "@testing-library/jest-dom"]
  },
  "include": ["src", "vitest.config.ts", "vitest.setup.ts"]
}
```

- [ ] **Step 4: Create vitest.config.ts**

```ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./vitest.setup.ts'],
  },
});
```

- [ ] **Step 5: Create vitest.setup.ts**

```ts
import '@testing-library/jest-dom/vitest';
```

- [ ] **Step 6: Install deps**

Run: `pnpm install` (from repo root)
Expected: completes; `@helpbee/ui` now has vitest + RTL.

- [ ] **Step 7: Commit**

```bash
git add packages/ui/package.json packages/ui/tsconfig.json packages/ui/vitest.config.ts packages/ui/vitest.setup.ts pnpm-lock.yaml
git commit -m "chore(ui): add test tooling, exports map, peer deps"
```

---

## Task 1: `cn()` utility (TDD)

**Files:**
- Create: `packages/ui/src/utils/cn.ts`
- Test: `packages/ui/src/utils/cn.test.ts`

- [ ] **Step 1: Write the failing test**

`packages/ui/src/utils/cn.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { cn } from './cn';

describe('cn', () => {
  it('merges conflicting tailwind classes, last wins', () => {
    expect(cn('px-2', 'px-4')).toBe('px-4');
  });
  it('drops falsy values and joins the rest', () => {
    expect(cn('text-bee-black', false && 'hidden', undefined, 'font-bold')).toBe(
      'text-bee-black font-bold',
    );
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @helpbee/ui test -- cn`
Expected: FAIL — `Failed to resolve import "./cn"`.

- [ ] **Step 3: Write minimal implementation**

`packages/ui/src/utils/cn.ts`:
```ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @helpbee/ui test -- cn`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/ui/src/utils/cn.ts packages/ui/src/utils/cn.test.ts
git commit -m "feat(ui): add cn class-merge util"
```

---

## Task 2: Design tokens + Tailwind preset

**Files:**
- Create: `packages/ui/src/tokens/colors.ts`
- Create: `packages/ui/src/tokens/typography.ts`
- Create: `packages/ui/src/tokens/tailwind.preset.ts`
- Test: `packages/ui/src/tokens/tokens.test.ts`

- [ ] **Step 1: Write the failing test**

`packages/ui/src/tokens/tokens.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import preset from './tailwind.preset';
import { honey, bee } from './colors';

describe('tokens', () => {
  it('anchors honey-500 to the Figma primary', () => {
    expect(honey[500]).toBe('#E49A03');
    expect(bee.black).toBe('#2D1E00');
  });
  it('exposes honey + bee colors and font families on the preset', () => {
    const colors = preset.theme?.extend?.colors as Record<string, unknown>;
    expect(colors.honey).toMatchObject({ 500: '#E49A03' });
    expect(colors.bee).toMatchObject({ black: '#2D1E00' });
    const fonts = preset.theme?.extend?.fontFamily as Record<string, string[]>;
    expect(fonts.sans[0]).toContain('--font-sans');
    expect(fonts.logo[0]).toContain('--font-logo');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @helpbee/ui test -- tokens`
Expected: FAIL — cannot resolve `./tailwind.preset`.

- [ ] **Step 3a: Create colors.ts**

`packages/ui/src/tokens/colors.ts`:
```ts
/** Figma-derived palette (spec §4). honey-500 = Figma primary #E49A03. */
export const honey = {
  50: '#FFFBF0',
  100: '#FFEDC7',
  200: '#FBE3A8',
  300: '#F7C863',
  400: '#F0B23B',
  500: '#E49A03',
  600: '#C2850A',
  700: '#9B6A08',
  800: '#74500A',
  900: '#4D360A',
} as const;

export const bee = {
  black: '#2D1E00', // headings / strong text
  brown: '#6B4423', // secondary text
} as const;

/** Warm surface tints observed in the Figma frames. */
export const surface = {
  cream: '#FFF1CE', // gradient / hero wash
  sand: '#E4D3B9', // footer band
  tip: '#FFEECB', // TIP box (how-it-works)
  pill: '#FCF5E0', // benefit pills (pricing)
  row: '#F9EBD0', // compare-table row
} as const;
```

- [ ] **Step 3b: Create typography.ts**

`packages/ui/src/tokens/typography.ts`:
```ts
/** Fonts are self-hosted by the app and injected via CSS variables.
 *  The preset only references the variable names (spec §4). */
export const fontFamily = {
  sans: ['var(--font-sans)', 'system-ui', 'sans-serif'],
  logo: ['var(--font-logo)', 'var(--font-sans)', 'sans-serif'],
} as const;
```

- [ ] **Step 3c: Create tailwind.preset.ts**

`packages/ui/src/tokens/tailwind.preset.ts`:
```ts
import type { Config } from 'tailwindcss';
import { honey, bee, surface } from './colors';
import { fontFamily } from './typography';

/** Single source of truth for the HelpBee palette/typography.
 *  Consumed by apps/web (and later apps/admin) via `presets: [require('@helpbee/ui/tailwind.preset')]`. */
const preset = {
  theme: {
    extend: {
      colors: {
        honey,
        bee,
        surface,
        primary: honey,
      },
      fontFamily: {
        sans: [...fontFamily.sans],
        logo: [...fontFamily.logo],
      },
      borderRadius: {
        xl: '0.875rem',
        '2xl': '1.25rem',
        '3xl': '1.75rem',
      },
    },
  },
} satisfies Partial<Config>;

export default preset;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @helpbee/ui test -- tokens`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/ui/src/tokens/
git commit -m "feat(ui): add Figma-derived tokens + tailwind preset"
```

---

## Task 3: Button (TDD)

**Files:**
- Create: `packages/ui/src/components/Button.tsx`
- Test: `packages/ui/src/components/Button.test.tsx`

- [ ] **Step 1: Write the failing test**

`packages/ui/src/components/Button.test.tsx`:
```tsx
import { render, screen } from '@testing-library/react';
import { createRef } from 'react';
import { describe, expect, it } from 'vitest';
import { Button } from './Button';

describe('Button', () => {
  it('renders its children as a button', () => {
    render(<Button>지금 시작</Button>);
    expect(screen.getByRole('button', { name: '지금 시작' })).toBeInTheDocument();
  });
  it('applies the requested variant class', () => {
    render(<Button variant="outline">x</Button>);
    expect(screen.getByRole('button').className).toContain('border-honey-500');
  });
  it('forwards ref and honors disabled', () => {
    const ref = createRef<HTMLButtonElement>();
    render(
      <Button ref={ref} disabled>
        x
      </Button>,
    );
    expect(ref.current).toBeInstanceOf(HTMLButtonElement);
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @helpbee/ui test -- Button`
Expected: FAIL — cannot resolve `./Button`.

- [ ] **Step 3: Write minimal implementation**

`packages/ui/src/components/Button.tsx`:
```tsx
import { cva, type VariantProps } from 'class-variance-authority';
import { forwardRef, type ButtonHTMLAttributes } from 'react';
import { cn } from '../utils/cn';

const buttonVariants = cva(
  'inline-flex items-center justify-center font-semibold transition-colors rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-500 focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none',
  {
    variants: {
      variant: {
        primary: 'bg-honey-500 text-white hover:bg-honey-600',
        outline: 'border border-honey-500 text-honey-600 bg-transparent hover:bg-honey-50',
        white: 'bg-white text-bee-black shadow-sm hover:bg-honey-50',
        ghost: 'text-bee-black hover:bg-honey-50',
      },
      size: {
        sm: 'h-10 px-4 text-base',
        md: 'h-12 px-6 text-lg',
        lg: 'h-14 px-8 text-xl',
      },
    },
    defaultVariants: { variant: 'primary', size: 'md' },
  },
);

export interface ButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, type = 'button', ...props }, ref) => (
    <button
      ref={ref}
      type={type}
      className={cn(buttonVariants({ variant, size }), className)}
      {...props}
    />
  ),
);
Button.displayName = 'Button';

export { buttonVariants };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @helpbee/ui test -- Button`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/ui/src/components/Button.tsx packages/ui/src/components/Button.test.tsx
git commit -m "feat(ui): add Button primitive"
```

---

## Task 4: Card

**Files:**
- Create: `packages/ui/src/components/Card.tsx`
- Test: `packages/ui/src/components/Card.test.tsx`

- [ ] **Step 1: Write the failing test**

`packages/ui/src/components/Card.test.tsx`:
```tsx
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Card } from './Card';

describe('Card', () => {
  it('renders children inside a rounded container and merges className', () => {
    render(<Card className="p-8">내용</Card>);
    const el = screen.getByText('내용');
    expect(el.className).toContain('rounded-2xl');
    expect(el.className).toContain('p-8');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @helpbee/ui test -- Card`
Expected: FAIL — cannot resolve `./Card`.

- [ ] **Step 3: Write minimal implementation**

`packages/ui/src/components/Card.tsx`:
```tsx
import { forwardRef, type HTMLAttributes } from 'react';
import { cn } from '../utils/cn';

export type CardProps = HTMLAttributes<HTMLDivElement>;

export const Card = forwardRef<HTMLDivElement, CardProps>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn('rounded-2xl bg-white', className)} {...props} />
));
Card.displayName = 'Card';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @helpbee/ui test -- Card`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/ui/src/components/Card.tsx packages/ui/src/components/Card.test.tsx
git commit -m "feat(ui): add Card primitive"
```

---

## Task 5: Badge

**Files:**
- Create: `packages/ui/src/components/Badge.tsx`
- Test: `packages/ui/src/components/Badge.test.tsx`

- [ ] **Step 1: Write the failing test**

`packages/ui/src/components/Badge.test.tsx`:
```tsx
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Badge } from './Badge';

describe('Badge', () => {
  it('renders label and applies solid variant by default', () => {
    render(<Badge>추천</Badge>);
    const el = screen.getByText('추천');
    expect(el.className).toContain('bg-honey-500');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @helpbee/ui test -- Badge`
Expected: FAIL — cannot resolve `./Badge`.

- [ ] **Step 3: Write minimal implementation**

`packages/ui/src/components/Badge.tsx`:
```tsx
import { cva, type VariantProps } from 'class-variance-authority';
import { forwardRef, type HTMLAttributes } from 'react';
import { cn } from '../utils/cn';

const badgeVariants = cva(
  'inline-flex items-center rounded-full px-3 py-1 text-sm font-semibold',
  {
    variants: {
      variant: {
        solid: 'bg-honey-500 text-white',
        soft: 'bg-honey-100 text-honey-700',
      },
    },
    defaultVariants: { variant: 'solid' },
  },
);

export interface BadgeProps
  extends HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

export const Badge = forwardRef<HTMLSpanElement, BadgeProps>(
  ({ className, variant, ...props }, ref) => (
    <span ref={ref} className={cn(badgeVariants({ variant }), className)} {...props} />
  ),
);
Badge.displayName = 'Badge';

export { badgeVariants };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @helpbee/ui test -- Badge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/ui/src/components/Badge.tsx packages/ui/src/components/Badge.test.tsx
git commit -m "feat(ui): add Badge primitive"
```

---

## Task 6: Input

**Files:**
- Create: `packages/ui/src/components/Input.tsx`
- Test: `packages/ui/src/components/Input.test.tsx`

- [ ] **Step 1: Write the failing test**

`packages/ui/src/components/Input.test.tsx`:
```tsx
import { render, screen } from '@testing-library/react';
import { createRef } from 'react';
import { describe, expect, it } from 'vitest';
import { Input } from './Input';

describe('Input', () => {
  it('forwards ref (RHF register compatible) and spreads props', () => {
    const ref = createRef<HTMLInputElement>();
    render(<Input ref={ref} placeholder="이름" />);
    expect(ref.current).toBeInstanceOf(HTMLInputElement);
    expect(screen.getByPlaceholderText('이름')).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @helpbee/ui test -- Input`
Expected: FAIL — cannot resolve `./Input`.

- [ ] **Step 3: Write minimal implementation**

`packages/ui/src/components/Input.tsx`:
```tsx
import { forwardRef, type InputHTMLAttributes } from 'react';
import { cn } from '../utils/cn';

export type InputProps = InputHTMLAttributes<HTMLInputElement>;

export const Input = forwardRef<HTMLInputElement, InputProps>(({ className, ...props }, ref) => (
  <input
    ref={ref}
    className={cn(
      'h-12 w-full rounded-xl border border-black/20 bg-white px-4 text-lg text-bee-black placeholder:text-[#AFAFAF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-500',
      className,
    )}
    {...props}
  />
));
Input.displayName = 'Input';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @helpbee/ui test -- Input`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/ui/src/components/Input.tsx packages/ui/src/components/Input.test.tsx
git commit -m "feat(ui): add Input primitive"
```

---

## Task 7: Textarea

**Files:**
- Create: `packages/ui/src/components/Textarea.tsx`
- Test: `packages/ui/src/components/Textarea.test.tsx`

- [ ] **Step 1: Write the failing test**

`packages/ui/src/components/Textarea.test.tsx`:
```tsx
import { render, screen } from '@testing-library/react';
import { createRef } from 'react';
import { describe, expect, it } from 'vitest';
import { Textarea } from './Textarea';

describe('Textarea', () => {
  it('forwards ref and renders as a textarea', () => {
    const ref = createRef<HTMLTextAreaElement>();
    render(<Textarea ref={ref} placeholder="문의 내용" />);
    expect(ref.current).toBeInstanceOf(HTMLTextAreaElement);
    expect(screen.getByPlaceholderText('문의 내용')).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @helpbee/ui test -- Textarea`
Expected: FAIL — cannot resolve `./Textarea`.

- [ ] **Step 3: Write minimal implementation**

`packages/ui/src/components/Textarea.tsx`:
```tsx
import { forwardRef, type TextareaHTMLAttributes } from 'react';
import { cn } from '../utils/cn';

export type TextareaProps = TextareaHTMLAttributes<HTMLTextAreaElement>;

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(
  ({ className, rows = 5, ...props }, ref) => (
    <textarea
      ref={ref}
      rows={rows}
      className={cn(
        'w-full rounded-2xl border border-black/20 bg-white px-4 py-3 text-lg text-bee-black placeholder:text-black/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-500',
        className,
      )}
      {...props}
    />
  ),
);
Textarea.displayName = 'Textarea';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @helpbee/ui test -- Textarea`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/ui/src/components/Textarea.tsx packages/ui/src/components/Textarea.test.tsx
git commit -m "feat(ui): add Textarea primitive"
```

---

## Task 8: Skeleton

**Files:**
- Create: `packages/ui/src/components/Skeleton.tsx`
- Test: `packages/ui/src/components/Skeleton.test.tsx`

- [ ] **Step 1: Write the failing test**

`packages/ui/src/components/Skeleton.test.tsx`:
```tsx
import { render } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Skeleton } from './Skeleton';

describe('Skeleton', () => {
  it('renders a pulsing placeholder and merges className', () => {
    const { container } = render(<Skeleton className="h-6 w-24" />);
    const el = container.firstChild as HTMLElement;
    expect(el.className).toContain('animate-pulse');
    expect(el.className).toContain('h-6');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @helpbee/ui test -- Skeleton`
Expected: FAIL — cannot resolve `./Skeleton`.

- [ ] **Step 3: Write minimal implementation**

`packages/ui/src/components/Skeleton.tsx`:
```tsx
import { type HTMLAttributes } from 'react';
import { cn } from '../utils/cn';

export type SkeletonProps = HTMLAttributes<HTMLDivElement>;

export function Skeleton({ className, ...props }: SkeletonProps) {
  return <div className={cn('animate-pulse rounded-md bg-honey-100', className)} {...props} />;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @helpbee/ui test -- Skeleton`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/ui/src/components/Skeleton.tsx packages/ui/src/components/Skeleton.test.tsx
git commit -m "feat(ui): add Skeleton primitive"
```

---

## Task 9: Public barrel + full verification

**Files:**
- Modify: `packages/ui/src/index.ts` (replace `UI_VERSION` stub)

- [ ] **Step 1: Replace index.ts with the named-export barrel**

`packages/ui/src/index.ts`:
```ts
export { cn } from './utils/cn';

export { honey, bee, surface } from './tokens/colors';
export { fontFamily } from './tokens/typography';

export { Button, buttonVariants, type ButtonProps } from './components/Button';
export { Card, type CardProps } from './components/Card';
export { Badge, badgeVariants, type BadgeProps } from './components/Badge';
export { Input, type InputProps } from './components/Input';
export { Textarea, type TextareaProps } from './components/Textarea';
export { Skeleton, type SkeletonProps } from './components/Skeleton';
```

- [ ] **Step 2: Run the full test suite**

Run: `pnpm --filter @helpbee/ui test`
Expected: PASS — all suites (cn, tokens, Button, Card, Badge, Input, Textarea, Skeleton).

- [ ] **Step 3: Run typecheck**

Run: `pnpm --filter @helpbee/ui typecheck`
Expected: no errors. (If `eslint` isn't configured yet in this package, skip `lint`; do not block on it.)

- [ ] **Step 4: Verify the barrel resolves from a consumer perspective**

Run: `node --input-type=module -e "import('@helpbee/ui').then(m => console.log(Object.keys(m).sort().join(',')))"`
Expected: prints `Badge,Button,Card,Input,Skeleton,Textarea,badgeVariants,bee,buttonVariants,cn,fontFamily,honey,surface` (order may vary). If Node can't resolve TS directly, this is fine — the real consumer (`apps/web`) transpiles via Next; instead confirm with: `pnpm --filter @helpbee/ui test && pnpm --filter @helpbee/ui typecheck` both green.

- [ ] **Step 5: Commit**

```bash
git add packages/ui/src/index.ts
git commit -m "feat(ui): export tokens + primitives from package barrel"
```

---

## Self-Review (done while writing)

- **Spec coverage:** §4 tokens → Task 2 ✅. §6 ui primitives (Button/Card/Input/Textarea/Badge/Skeleton) → Tasks 3–8 ✅. Accordion/Select/Checkbox → explicitly deferred to the contact-page plan (documented in Scope note) ✅. `cn` util → Task 1 ✅. `exports`/`./tailwind.preset` → Task 0 ✅.
- **Placeholder scan:** every code step shows complete file contents; no TBD/TODO.
- **Type consistency:** `cn` signature, `honey[500]`, `bee.black`, `buttonVariants`/`badgeVariants`, and all `*Props` names are identical across the test, implementation, and barrel.
- **Test-design note:** logic (`cn`, token shape) is asserted directly; components get render/ref/variant smoke tests. Pixel-fidelity to Figma is verified visually once `apps/web` renders them (Plan 3), not via brittle class-string snapshots.

## Definition of Done (Plan 1)

- `pnpm --filter @helpbee/ui test` green; `pnpm --filter @helpbee/ui typecheck` clean.
- `@helpbee/ui` exports `cn`, tokens, and 6 primitives; `./tailwind.preset` importable.
- All work committed on `feature/web-frontend-mvp` in small commits.

---

## Roadmap — subsequent plans (authored just-in-time after Plan 1 lands)

> Outlines only. Full bite-sized tasks are written when each plan starts, using the exact token/component APIs finalized above.

**Plan 2 — Web App Shell** (`docs/superpowers/plans/2026-06-17-web-shell.md`)
- Install `next-intl`, `react-hook-form`, `zod`, blog/MDX lib (final choice confirmed here).
- `tailwind.config.ts` (preset import) + globals.css.
- Self-host fonts (S-Core Dream, Jua) via `next/font/local`; set `--font-sans`/`--font-logo`; source confirmed before download.
- `src/middleware.ts` (next-intl, ko default, en skeleton).
- Remove root `app/` stub; create `src/app/[locale]/layout.tsx`.
- Components: `Header` (nav + download CTA + LanguageSwitcher + mobile drawer + SkipLink), `Footer`, `CookieConsent`, `DownloadCTABand`, `StoreBadge`.
- `src/lib/`: `seo.ts` (metadata+hreflang helper), `analytics.ts` (GA4/Hotjar consent-gated), `inquiries.ts` (submit stub), i18n config.
- `.env.example` entries.
- **DoD:** site runs, every locale route renders global chrome, `pnpm --filter web build` green.

**Plan 3 — Figma 4 Pages** (`docs/superpowers/plans/2026-06-17-web-marketing-pages.md`)
- Add Radix-based `Accordion`, `Select`, `Checkbox` to `@helpbee/ui` (consumers appear here).
- Home (Hero/IntroCard/FeatureCard/RecommendCard/StatsBlock/QuoteBlock).
- How-it-works (StepCard/TipBox).
- Pricing (PricingCard/PricingCompareTable/BenefitPills).
- Contact/FAQ (FaqSearch/FaqList/ContactChannelCard/ContactForm with zod + consent, submit disabled).
- All copy in `messages/{ko,en}.json` (dummy); responsive mobile-first matching Figma at lg/xl.
- **DoD:** 4 pages match Figma on desktop, no breakage on mobile, form validates.

**Plan 4 — Legal / SEO / Blog** (`docs/superpowers/plans/2026-06-17-web-legal-seo.md`)
- `download`, `about`, `privacy`, `terms` (dummy bodies), `blog` + `blog/[slug]` (MDX skeleton + 1 dummy post), `[...not-found]` 404.
- `sitemap.ts`, `robots.ts` (en noindex / sitemap-excluded).
- Fix token tables in `packages/ui/CLAUDE.md` + `apps/web/CLAUDE.md` to Figma values.
- Add `docs/05-implementation/2026-06-17-web-frontend-mvp.md` record; open PR `feature/web-frontend-mvp → develop`.
- **DoD:** all routes present, SEO infra emits, Lighthouse spot-check, PR opened.
