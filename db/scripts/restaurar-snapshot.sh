#!/usr/bin/env bash
# =============================================================================
# restaurar-snapshot.sh — Deja la base lista a partir de db/dumps/vet_demo.sql.gz
#
# El atajo para levantar el ERP en una máquina nueva sin esperar las 34
# migraciones. Equivale a `apply-migrations.sh` sobre una base vacía.
#
# BORRA el contenido de la base destino. Por eso pide confirmación salvo que se
# pase FORCE=1.
#
# Uso:
#   bash db/scripts/restaurar-snapshot.sh
#   DB_NAME=vet_local FORCE=1 bash db/scripts/restaurar-snapshot.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/_psql.sh"

DUMP="$REPO_DIR/db/dumps/vet_demo.sql.gz"
[[ -f "$DUMP" ]] || { echo "✗ No encuentro $DUMP" >&2; exit 1; }

echo "→ Destino: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
head -3 <(gzip -dc "$DUMP") | sed 's/^/  /'

if [[ "${FORCE:-0}" != "1" ]]; then
  read -rp "Esto BORRA el contenido de '$DB_NAME'. ¿Seguir? [s/N] " r
  [[ "$r" == "s" || "$r" == "S" ]] || { echo "Cancelado."; exit 0; }
fi

admin_psql() {
  if [[ "$PSQL_MODE" == "host" ]]; then
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres --quiet --no-psqlrc "$@"
  else
    docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
      psql -U "$DB_USER" -d postgres --quiet --no-psqlrc "$@"
  fi
}

admin_psql -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" -tA | grep -q 1 \
  || admin_psql -c "CREATE DATABASE $DB_NAME;" > /dev/null

echo "→ Restaurando"
gzip -dc "$DUMP" | run_psql > /dev/null

# El volcado va sin ACLs: el rol de la aplicación y sus permisos se rehacen aquí.
echo "→ Rol de aplicación (vet_app_user) y permisos"
run_psql -f "$REPO_DIR/db/migrations/90_grants.sql" > /dev/null

echo "✓ Base '$DB_NAME' lista."
echo
echo "  Falta fijar la contraseña del rol con el que se conecta el backend:"
echo "    ALTER ROLE vet_app_user WITH PASSWORD '<secreto>';"
echo "  y ponerla en backend/.env  →  DATABASE_URL"
