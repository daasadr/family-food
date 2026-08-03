#!/usr/bin/env bash
#
# Denní záloha databáze (zadání, sekce 7).
#
# Nasazení do cronu (jako uživatel, který vlastní projekt):
#   crontab -e
#   15 3 * * *  /opt/familyfood/deploy/backup.sh >> /var/log/familyfood-backup.log 2>&1
#
# Zálohy se ukládají mimo Docker volume, aby přežily `docker compose down -v`.

set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${FAMILYFOOD_BACKUP_DIR:-$DEPLOY_DIR/backups}"
KEEP_DAYS="${FAMILYFOOD_BACKUP_KEEP_DAYS:-30}"

# shellcheck disable=SC1091
set -a; source "$DEPLOY_DIR/.env"; set +a

mkdir -p "$BACKUP_DIR"

STAMP="$(date +%Y-%m-%d_%H%M)"
TARGET="$BACKUP_DIR/family_food_$STAMP.sql.gz"

echo "[$(date -Is)] Zálohuji do $TARGET"

# -T = bez TTY, jinak by cron skončil chybou "the input device is not a TTY".
docker compose -f "$DEPLOY_DIR/docker-compose.yml" --env-file "$DEPLOY_DIR/.env" \
  exec -T db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists \
  | gzip > "$TARGET.part"

# Přejmenování až po úspěchu — nedokončený dump se nikdy netváří jako platná záloha.
mv "$TARGET.part" "$TARGET"

SIZE="$(du -h "$TARGET" | cut -f1)"
echo "[$(date -Is)] Hotovo ($SIZE)"

# Úklid starých záloh.
find "$BACKUP_DIR" -name 'family_food_*.sql.gz' -mtime "+$KEEP_DAYS" -delete
find "$BACKUP_DIR" -name '*.part' -mtime +1 -delete

echo "[$(date -Is)] Zálohy v $BACKUP_DIR: $(find "$BACKUP_DIR" -name 'family_food_*.sql.gz' | wc -l)"
