#!/usr/bin/env bash
# =============================================================================
# apply-migrations.sh — Aplica todas las migraciones de db/migrations/ en orden
# alfanumérico (que es el orden lógico: 0x tablas → 1x helpers → 2x-5x SPs →
# 9x grants y datos de referencia).
#
# Defaults alineados con infra/docker/docker-compose.dev.yml:
#   DB_HOST=localhost DB_PORT=5435 DB_USER=postgres DB_PASSWORD=postgres DB_NAME=vet_demo
#
# Si el host no tiene psql instalado, usa el del contenedor veterp_postgres_dev.
#
# Variables opcionales:
#   SEED_DEMO=1          además aplica db/seeds/*.sql: las dos empresas de
#                        demostración, sus usuarios (clave Demo2026!) y su
#                        operación. Nunca en producción. Solo se acepta contra
#                        una base cuyo nombre diga demo/dev/test/ci/snapshot,
#                        salvo FORCE_DEMO=yes.
#   VET_APP_PASSWORD     fija la contraseña de vet_app_user (el rol con el que
#                        se conecta el backend). Sin ella el rol queda con la
#                        aleatoria que le puso 90_grants.sql, o con la que ya
#                        tuviera.
#
# Uso:
#   bash db/scripts/apply-migrations.sh                      # solo esquema
#   SEED_DEMO=1 bash db/scripts/apply-migrations.sh          # + demo (dev)
#   DB_HOST=prod-host DB_NAME=veterp VET_APP_PASSWORD=… bash db/scripts/apply-migrations.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_psql.sh"

MIGRATIONS_DIR="$SCRIPT_DIR/../migrations"
SEEDS_DIR="$SCRIPT_DIR/../seeds"
SEED_DEMO="${SEED_DEMO:-0}"
[[ -d "$MIGRATIONS_DIR" ]] || { echo "✗ No encuentro $MIGRATIONS_DIR" >&2; exit 1; }

if [[ "$SEED_DEMO" == "1" && "${FORCE_DEMO:-no}" != "yes" ]]; then
  case "$DB_NAME" in
    *demo*|*dev*|*test*|*ci*|*snapshot*) ;;
    *) echo "✗ SEED_DEMO=1 contra '$DB_NAME': no parece una base de desarrollo." >&2
       echo "  Los datos de demo crean usuarios con contraseña conocida." >&2
       echo "  Si de verdad es lo que quieres: FORCE_DEMO=yes" >&2
       exit 1 ;;
  esac
fi

echo "→ Aplicando migraciones contra $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME  [psql: $PSQL_MODE]"

# LC_ALL=C: el orden de las migraciones debe ser byte a byte. Con el locale del
# sistema (es_ES) el glob ignora guiones bajos y puntos al ordenar, lo que puede
# colar un archivo antes que otro del que depende.
listar_sql() {
  shopt -s nullglob
  LC_ALL=C printf '%s\n' "$1"/*.sql | LC_ALL=C sort
  shopt -u nullglob
}

mapfile -t files < <(listar_sql "$MIGRATIONS_DIR")
[[ ${#files[@]} -gt 0 && -n "${files[0]}" ]] || { echo "✗ No hay archivos .sql en $MIGRATIONS_DIR" >&2; exit 1; }

for f in "${files[@]}"; do
  echo "  · $(basename "$f")"
  run_psql -f "$f" > /dev/null
done
echo "✓ ${#files[@]} migraciones aplicadas."

if [[ "$SEED_DEMO" == "1" ]]; then
  mapfile -t seeds < <(listar_sql "$SEEDS_DIR")
  for f in "${seeds[@]}"; do
    [[ -n "$f" ]] || continue
    echo "  · seeds/$(basename "$f")"
    run_psql -f "$f" > /dev/null
  done
  echo "✓ Datos de demostración aplicados (usuarios con clave Demo2026!)."
fi

if [[ -n "${VET_APP_PASSWORD:-}" ]]; then
  # La clave no pasa por la línea de comandos (la vería `ps`) ni se interpola a
  # mano en el SQL: psql la lee del entorno con \getenv y :'var' la escapa.
  export VET_APP_PASSWORD
  PSQL_DOCKER_ENV=(-e VET_APP_PASSWORD)
  run_psql > /dev/null <<'SQL'
\getenv app_pwd VET_APP_PASSWORD
ALTER ROLE vet_app_user WITH LOGIN PASSWORD :'app_pwd';
SQL
  echo "✓ Contraseña de vet_app_user fijada desde VET_APP_PASSWORD."
fi
