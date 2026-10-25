#!/usr/bin/env bash
# =============================================================================
# _conexion.sh — a qué base apuntan backup.sh, restore.sh y restore-test.sh.
#
# A diferencia de _psql.sh (pensado para desarrollo), aquí NO hay defaults de
# desarrollo implícitos: un backup de producción que por un default olvidado
# respalda la base de demo "funciona", deja un archivo y nadie se entera hasta
# el día que hace falta restaurar.
#
# Configuración (entorno, o un archivo con las mismas variables en
# VETERP_BACKUP_ENV — por defecto /etc/veterp/backup.env si existe):
#
#   DB_NAME        obligatoria.
#   DB_CONTAINER   contenedor de Postgres: pg_dump/psql corren dentro con
#                  `docker exec` (caso del compose de producción).
#   DB_HOST        o bien, conexión directa con las herramientas del host.
#   DB_PORT        5432    DB_USER  postgres
#   DB_PASSWORD    opcional si hay ~/.pgpass (o si el contenedor confía en
#                  conexiones locales).
#
# Solo si no se configura NADA y está corriendo el contenedor de desarrollo
# (veterp_postgres_dev) se usa ese, avisándolo en voz alta.
#
# No ejecutable por sí solo: se hace `source` desde los demás scripts.
# =============================================================================

VETERP_BACKUP_ENV="${VETERP_BACKUP_ENV:-/etc/veterp/backup.env}"
# Se carga una sola vez: restore-test.sh llama a restore.sh con otro DB_NAME,
# y el archivo no debe pisarlo.
if [[ -f "$VETERP_BACKUP_ENV" && -z "${VETERP_BACKUP_ENV_CARGADO:-}" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$VETERP_BACKUP_ENV"; set +a
  export VETERP_BACKUP_ENV_CARGADO=1
fi

if [[ -z "${DB_NAME:-}" && -z "${DB_CONTAINER:-}" && -z "${DB_HOST:-}" ]]; then
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx veterp_postgres_dev; then
    echo "⚠ Sin configuración: se usa la base de DESARROLLO (veterp_postgres_dev/vet_demo)." >&2
    echo "  En producción define DB_NAME y DB_CONTAINER o DB_HOST (ver despliegue.md)." >&2
    DB_CONTAINER=veterp_postgres_dev
    DB_NAME=vet_demo
    DB_PASSWORD="${DB_PASSWORD:-postgres}"
  fi
fi

: "${DB_NAME:?define DB_NAME (la base a respaldar/restaurar)}"
if [[ -z "${DB_CONTAINER:-}" && -z "${DB_HOST:-}" ]]; then
  echo "✗ Define DB_CONTAINER (Postgres en Docker) o DB_HOST (conexión directa)." >&2
  exit 2
fi
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
[[ -n "${DB_PASSWORD:-}" ]] && export PGPASSWORD="$DB_PASSWORD"

if [[ -n "${DB_CONTAINER:-}" ]]; then
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER" || {
    echo "✗ El contenedor '$DB_CONTAINER' no está corriendo." >&2; exit 2; }
  CONEXION_DESC="docker:$DB_CONTAINER/$DB_NAME"
else
  CONEXION_DESC="$DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
fi

# pg <herramienta> [args…] — ejecuta pg_dump / pg_restore / psql contra la
# base configurada. En modo contenedor la entrada y la salida van por
# stdin/stdout: el contenedor no ve el sistema de archivos del host.
# La base se pasa como argumento (-d) por quien llama.
pg() {
  local bin="$1"; shift
  if [[ -n "${DB_CONTAINER:-}" ]]; then
    local envs=()
    [[ -n "${PGPASSWORD:-}" ]] && envs=(-e PGPASSWORD)
    docker exec -i "${envs[@]}" "$DB_CONTAINER" "$bin" -U "$DB_USER" "$@"
  else
    "$bin" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$@"
  fi
}

log() { printf '%s  %s\n' "$(date '+%F %T')" "$*" | tee -a "${LOG_FILE:-/dev/null}" >&2; }
