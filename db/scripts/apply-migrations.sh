#!/usr/bin/env bash
# =============================================================================
# apply-migrations.sh — Aplica todas las migraciones de db/migrations/ en orden
# alfanumérico (que es el orden lógico: 0x tablas → 1x helpers → 2x-5x SPs →
# 9x grants/seeds).
#
# Defaults alineados con infra/docker/docker-compose.dev.yml:
#   DB_HOST=localhost DB_PORT=5435 DB_USER=postgres DB_PASSWORD=postgres DB_NAME=vet_demo
#
# Si el host no tiene psql instalado, usa el del contenedor veterp_postgres_dev.
#
# Uso:
#   bash db/scripts/apply-migrations.sh
#   DB_HOST=prod-host DB_NAME=vet_prod bash db/scripts/apply-migrations.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_psql.sh"

MIGRATIONS_DIR="$SCRIPT_DIR/../migrations"
[[ -d "$MIGRATIONS_DIR" ]] || { echo "✗ No encuentro $MIGRATIONS_DIR" >&2; exit 1; }

echo "→ Aplicando migraciones contra $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME  [psql: $PSQL_MODE]"

# LC_ALL=C: el orden de las migraciones debe ser byte a byte. Con el locale del
# sistema (es_ES) el glob ignora guiones bajos y puntos al ordenar, lo que puede
# colar un archivo antes que otro del que depende.
shopt -s nullglob
mapfile -t files < <(LC_ALL=C printf '%s\n' "$MIGRATIONS_DIR"/*.sql | LC_ALL=C sort)
shopt -u nullglob
[[ ${#files[@]} -gt 0 ]] || { echo "✗ No hay archivos .sql en $MIGRATIONS_DIR" >&2; exit 1; }

for f in "${files[@]}"; do
  echo "  · $(basename "$f")"
  run_psql -f "$f" > /dev/null
done

echo "✓ ${#files[@]} migraciones aplicadas."
