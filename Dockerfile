# ============================================
# Oreko Production Dockerfile
# ============================================

FROM node:20.18-alpine AS base

RUN apk add --no-cache libc6-compat

RUN corepack enable \
    && corepack prepare pnpm@9.15.0 --activate


# ============================================
# Dependencies
# ============================================

FROM base AS deps

WORKDIR /app

RUN echo "node-linker=hoisted" > .npmrc

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

COPY apps/web/package.json ./apps/web/
COPY packages/database/package.json ./packages/database/
COPY packages/ui/package.json ./packages/ui/
COPY packages/utils/package.json ./packages/utils/
COPY packages/types/package.json ./packages/types/

RUN pnpm install --frozen-lockfile


# ============================================
# Builder
# ============================================

FROM base AS builder

WORKDIR /app

COPY --from=deps /app ./
COPY . .

RUN mkdir -p node_modules/@oreko \
    && ln -sf ../../../packages/database node_modules/@oreko/database \
    && ln -sf ../../../packages/ui node_modules/@oreko/ui \
    && ln -sf ../../../packages/utils node_modules/@oreko/utils \
    && ln -sf ../../../packages/types node_modules/@oreko/types

RUN ./node_modules/.bin/prisma generate \
    --schema=packages/database/prisma/schema.prisma

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV DOCKER_BUILD=1

RUN cd apps/web \
    && ../../node_modules/.bin/next build


# ============================================
# Production runner
# ============================================

FROM node:20.18-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

# Chromium required for PDF generation
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont

RUN addgroup --system --gid 1001 nodejs \
    && adduser --system --uid 1001 nextjs

# Next.js standalone runtime
COPY --from=builder /app/apps/web/.next/standalone ./

# Static assets
COPY --from=builder /app/apps/web/.next/static \
    ./apps/web/.next/static

COPY --from=builder /app/apps/web/public \
    ./apps/web/public

# Prisma schema - only retain if Oreko actually accesses it at runtime
COPY --from=builder /app/packages/database/prisma \
    ./packages/database/prisma

RUN mkdir -p /app/uploads \
    && chown -R nextjs:nodejs /app/uploads

USER nextjs

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME=0.0.0.0

CMD ["node", "apps/web/server.js"]