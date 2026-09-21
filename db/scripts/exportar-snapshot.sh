#!/usr/bin/env bash
# =============================================================================
# exportar-snapshot.sh — Genera db/dumps/vet_demo.sql.gz
#
# El volcado NO se saca de la base de desarrollo: se construye una base temporal
# aplicando las migraciones desde cero y se vuelca esa. Así el archivo siempre
# refleja lo que hay en db/migrations/ y no arrastra lo que cada quien haya
# probado en su máquina.
#
# Uso:  bash db/scripts/exportar-snapshot.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/_psql.sh"

TMP_DB="vet_snapshot_export"
SALIDA="$REPO_DIR/db/dumps/vet_demo.sql.gz"
mkdir -p "$(dirname "$SALIDA")"

admin_psql() {
  if [[ "$PSQL_MODE" == "host" ]]; then
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres --quiet --no-psqlrc "$@"
  else
    docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
      psql -U "$DB_USER" -d postgres --quiet --no-psqlrc "$@"
  fi
}

echo "→ Construyendo $TMP_DB desde db/migrations/"
admin_psql -c "DROP DATABASE IF EXISTS $TMP_DB;" -c "CREATE DATABASE $TMP_DB;" > /dev/null
DB_NAME="$TMP_DB" bash "$SCRIPT_DIR/apply-migrations.sh" | tail -1

COMMIT="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo desconocido)"
FECHA="$(date +%Y-%m-%d)"

echo "→ Volcando"
{
  echo "-- Snapshot de la base del ERP Veterinario"
  echo "-- Generado el $FECHA desde el commit $COMMIT con db/scripts/exportar-snapshot.sh"
  echo "-- Incluye esquema, catálogos y las dos empresas de demostración."
  echo "-- La fuente de verdad son las migraciones: si esto y db/migrations/ no"
  echo "-- coinciden, manda db/migrations/."
  echo
  if [[ "$PSQL_MODE" == "host" ]]; then
    PGPASSWORD="$DB_PASSWORD" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
      -d "$TMP_DB" --no-owner --no-acl --clean --if-exists
  else
    docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
      pg_dump -U "$DB_USER" -d "$TMP_DB" --no-owner --no-acl --clean --if-exists
  fi
} | gzip -9 > "$SALIDA"

admin_psql -c "DROP DATABASE IF EXISTS $TMP_DB;" > /dev/null

echo "✓ $SALIDA  ($(du -h "$SALIDA" | cut -f1), commit $COMMIT)"
