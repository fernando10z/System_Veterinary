#!/usr/bin/env bash
# =============================================================================
# restore.sh — Restaura un dump .dump sobre la BD indicada.
#
#   bash db/scripts/restore.sh db/backups/vet_demo_20260822_101500.dump
#
# --clean --if-exists: elimina los objetos existentes antes de recrearlos, así
# que SOBRESCRIBE la base de destino. Confirmar el DB_NAME antes de ejecutar.
# =============================================================================
set -euo pipefail

DUMP="${1:-}"
[[ -f "$DUMP" ]] || { echo "✗ Uso: restore.sh <archivo.dump>" >&2; exit 1; }

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5435}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
DB_NAME="${DB_NAME:-vet_demo}"
DB_CONTAINER="${DB_CONTAINER:-veterp_postgres_dev}"

export PGPASSWORD="$DB_PASSWORD"

echo "→ Restaurando $DUMP sobre $DB_NAME (se sobrescriben los objetos existentes)"

if command -v pg_restore >/dev/null 2>&1; then
  pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    --clean --if-exists --no-owner --no-privileges "$DUMP"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER"; then
  docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
    pg_restore -U "$DB_USER" -d "$DB_NAME" \
    --clean --if-exists --no-owner --no-privileges < "$DUMP"
else
  echo "✗ No hay pg_restore en el host ni el contenedor '$DB_CONTAINER' está corriendo." >&2
  exit 1
fi

echo "✓ Restaurado $DUMP en $DB_NAME"
