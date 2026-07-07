# syntax=docker/dockerfile:1
# HelpBee API (Hono) — beta 단일 EC2용 이미지 (plans/2026-07-07_배포인프라-절감모드.md PR-4)
#
# 런타임 = tsx (dev와 동일 경로). tsc 산출물(dist)은 사용하지 않는다:
#   - @helpbee/database·@helpbee/types 가 TS 소스(main: ./src/index.ts)를 직접 export
#   - tsc(moduleResolution: bundler) 산출물은 확장자 없는 ESM import 라 node 단독 실행 불가
#   (둘 다 2026-07-07 실측 — `node dist/index.js` → ERR_MODULE_NOT_FOUND)
#
# 빌드 컨텍스트 = 모노레포 루트:
#   docker build -f apps/api/Dockerfile -t helpbee-api .

FROM node:22-slim AS base
# CI(ci.yml)와 동일한 pnpm 메이저 버전 고정
RUN npm install -g pnpm@10

# ── deps: 워크스페이스 매니페스트만 먼저 복사해 설치 레이어 캐시 ────────────
# pnpm --frozen-lockfile 은 lockfile importers(워크스페이스 9개)와 파일시스템이
# 일치해야 하므로, 이미지에 안 들어가는 앱(web/admin/ai)의 package.json도 복사한다.
FROM base AS deps
WORKDIR /app
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY apps/api/package.json apps/api/
COPY apps/admin/package.json apps/admin/
COPY apps/ai/package.json apps/ai/
COPY apps/web/package.json apps/web/
COPY packages/config/package.json packages/config/
COPY packages/database/package.json packages/database/
COPY packages/types/package.json packages/types/
COPY packages/ui/package.json packages/ui/
# --prod: devDeps 제외. tsx 는 apps/api dependencies(런타임)라 포함된다.
# argon2 빌드 스크립트는 루트 package.json 의 pnpm.onlyBuiltDependencies 로 허용됨.
RUN pnpm install --frozen-lockfile --prod --filter "@helpbee/api..."

# ── runner ──────────────────────────────────────────────────────────────────
FROM node:22-slim AS runner
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps --chown=node:node /app ./
# 소스(TS)를 그대로 복사 — tsx 가 실행. packages/config 는 dev 전용이라 제외.
# tsconfig.json 도 미포함: @/ alias 미사용(실측 0건) + extends 대상(@helpbee/config)이
# --prod 설치에서 빠져 있어 오히려 해석 실패 리스크만 됨.
COPY --chown=node:node apps/api/src apps/api/src
COPY --chown=node:node packages/database/src packages/database/src
COPY --chown=node:node packages/database/migrations packages/database/migrations
COPY --chown=node:node packages/database/drizzle.config.ts packages/database/
COPY --chown=node:node packages/types/src packages/types/src
USER node
WORKDIR /app/apps/api
EXPOSE 3001
# node:22-slim 에는 curl/wget 이 없어 node 내장 fetch 로 헬스체크
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3001/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
# 마이그레이션(배포 스크립트가 1회성 실행):
#   docker compose run --rm --no-deps api ./node_modules/.bin/tsx ../../packages/database/src/migrate.ts
CMD ["./node_modules/.bin/tsx", "src/index.ts"]
