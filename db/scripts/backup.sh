#!/usr/bin/env bash
# =============================================================================
# backup.sh — Dump comprimido (formato custom) con timestamp en db/backups/.
#
# Si el host no tiene pg_dump, usa el del contenedor veterp_postgres_dev.
#
#   bash db/scripts/backup.sh
#   DB_NAME=veterp DB_HOST=prod-host bash db/scripts/backup.sh
# =============================================================================
set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5435}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
DB_NAME="${DB_NAME:-vet_demo}"
DB_CONTAINER="${DB_CONTAINER:-veterp_postgres_dev}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/../backups}"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/${DB_NAME}_$(date +%Y%m%d_%H%M%S).dump"

export PGPASSWORD="$DB_PASSWORD"

if command -v pg_dump >/dev/null 2>&1; then
  pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Fc -f "$OUT"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER"; then
  # El contenedor no ve el FS del host: el dump sale por stdout.
  docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
    pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$OUT"
else
  echo "✗ No hay pg_dump en el host ni el contenedor '$DB_CONTAINER' está corriendo." >&2
  exit 1
fi

echo "✓ Backup en $OUT ($(du -h "$OUT" | cut -f1))"
