#!/usr/bin/env bash
# =============================================================================
# _psql.sh — resuelve cómo invocar psql y expone la función `run_psql`.
#
# Prefiere el psql del host. Si no está instalado (caso habitual en esta
# máquina), cae al que trae el contenedor de Postgres vía `docker exec`, de modo
# que los scripts de db/ funcionan sin instalar postgresql-client.
#
# No ejecutable por sí solo: se hace `source` desde los demás scripts.
# =============================================================================

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5435}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
DB_NAME="${DB_NAME:-vet_demo}"
DB_CONTAINER="${DB_CONTAINER:-veterp_postgres_dev}"

export PGPASSWORD="$DB_PASSWORD"

if command -v psql >/dev/null 2>&1; then
  PSQL_MODE="host"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER"; then
  PSQL_MODE="docker"
else
  echo "✗ No hay psql en el host ni el contenedor '$DB_CONTAINER' está corriendo." >&2
  echo "  Levanta el stack:  docker compose -f infra/docker/docker-compose.dev.yml up -d" >&2
  exit 1
fi

# run_psql <args...>  — acepta -f archivo, -c "sql", etc.
# En modo docker el archivo se envía por stdin (el contenedor no ve el FS del host).
run_psql() {
  if [[ "$PSQL_MODE" == "host" ]]; then
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
         -v ON_ERROR_STOP=1 --quiet --no-psqlrc "$@"
  else
    local file=""
    local args=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -f) file="$2"; shift 2 ;;
        *)  args+=("$1"); shift ;;
      esac
    done
    if [[ -n "$file" ]]; then
      docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 --quiet --no-psqlrc \
        "${args[@]}" < "$file"
    else
      docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 --quiet --no-psqlrc "${args[@]}"
    fi
  fi
}
