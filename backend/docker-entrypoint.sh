#!/bin/sh
set -e

# Migrace se pouštějí při startu kontejneru, ne při buildu — build nemá
# přístup k produkční databázi. `migrate deploy` je idempotentní: už
# nasazené migrace přeskočí.
echo "Spouštím migrace databáze…"
npx prisma migrate deploy

# Globální galerie jídel. Seed přeskakuje položky, které už existují,
# takže ho lze pouštět při každém startu.
echo "Doplňuji globální galerii…"
node dist/seed.js || echo "Seed přeskočen (galerie už je naplněná nebo seed není přibalen)."

echo "Startuji API…"
exec node dist/index.js
