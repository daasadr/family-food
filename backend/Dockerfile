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
FROM node:22-slim AS deps

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# --- runtime -----------------------------------------------------------
FROM node:22-slim AS runner

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production

COPY package.json ./
COPY --from=deps /app/node_modules ./node_modules

# Prisma CLI (kvůli `migrate deploy` při startu) a vygenerovaný klient.
# Kopírují se z builderu, aby v obrazu nezůstaly ostatní vývojové balíčky.
COPY --from=builder /app/node_modules/prisma ./node_modules/prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma

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
