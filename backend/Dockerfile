# Backend image pro nasazení na VPS.
#
# Debian slim, ne alpine — Prisma i @node-rs/argon2 mají předkompilované
# binárky pro glibc; na musl by se musely kompilovat ze zdrojů.

# --- build -------------------------------------------------------------
FROM node:22-slim AS builder

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci

COPY prisma ./prisma
RUN npx prisma generate

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# --- produkční závislosti ----------------------------------------------
# Vlastní stage, aby se do běhového obrazu nedostaly tsx, vitest ani
# TypeScript. Prisma CLI je naopak v `dependencies`, protože ji entrypoint
# potřebuje na `migrate deploy` — a jen tak vznikne i správný odkaz
# v node_modules/.bin, bez kterého by se ji npx pokoušel stáhnout z internetu.
FROM node:22-slim AS deps

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
# Schéma musí být na místě dřív, než postinstall @prisma/client zkusí
# vygenerovat klienta.
COPY prisma ./prisma
RUN npm ci --omit=dev \
    && npx prisma generate \
    && npm cache clean --force

# --- runtime -----------------------------------------------------------
FROM node:22-slim AS runner

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production

COPY package.json ./
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY prisma ./prisma
COPY public ./public
COPY docker-entrypoint.sh ./

RUN chmod +x docker-entrypoint.sh \
    && chown -R node:node /app

USER node

EXPOSE 3000

# tini jako PID 1 — jinak Node nedostane SIGTERM a kontejner se ukončuje tvrdě.
ENTRYPOINT ["/usr/bin/tini", "--", "./docker-entrypoint.sh"]
