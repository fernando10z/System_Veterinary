#!/usr/bin/env bash
# =============================================================================
# restore-test.sh — Prueba que el último backup se puede restaurar.
#
# Un backup que nunca se restauró es una hipótesis. Este script toma el dump
# más reciente de BACKUP_DIR (o el que se le pase), lo restaura en una base
# desechable del mismo servidor, comprueba que la base tenga sentido y la
# borra. Pensado para correr en cron una vez por semana.
#
#   DB_CONTAINER=veterp-prod-postgres-1 DB_NAME=veterp bash db/scripts/restore-test.sh
#   … bash db/scripts/restore-test.sh db/backups/veterp_20260901_020000.dump
#
# KEEP=1 conserva la base de prueba para inspeccionarla.
# Sale con código distinto de 0 si la restauración o la comprobación fallan.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_conexion.sh"

BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/../backups}"
mkdir -p "$BACKUP_DIR"
LOG_FILE="$BACKUP_DIR/backup.log"
DUMP="${1:-}"
if [[ -z "$DUMP" ]]; then
  DUMP="$(ls -1t "$BACKUP_DIR"/"${DB_NAME}"_*.dump "$BACKUP_DIR"/"${DB_NAME}"_*.dump.gpg 2>/dev/null | head -1 || true)"
fi
[[ -n "$DUMP" && -f "$DUMP" ]] || { log "✗ restore-test: no hay backups de $DB_NAME en $BACKUP_DIR"; exit 1; }

ORIGEN="$DB_NAME"
PRUEBA="${ORIGEN}_restore_test_$(date +%Y%m%d%H%M%S)"

limpiar() {
  if [[ "${KEEP:-0}" != "1" ]]; then
    pg psql -d postgres -qc "DROP DATABASE IF EXISTS \"$PRUEBA\"" > /dev/null 2>&1 || true
  fi
}
trap limpiar EXIT
trap 'log "✗ restore-test FALLIDO ($DUMP) en la línea $LINENO: $BASH_COMMAND"' ERR

log "→ restore-test: $DUMP → base temporal $PRUEBA"
pg psql -d postgres -v ON_ERROR_STOP=1 -qc "CREATE DATABASE \"$PRUEBA\"" > /dev/null

DB_NAME="$PRUEBA" FORCE=1 VET_APP_PASSWORD="" bash "$SCRIPT_DIR/restore.sh" "$DUMP" > /dev/null

# Comprobaciones: el esquema está completo, los datos de referencia también y
# el rol de la aplicación puede llamar a los SPs (y solo a ellos).
RES="$(pg psql -d "$PRUEBA" -v ON_ERROR_STOP=1 -At --no-psqlrc <<'SQL'
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'app')                                     || '|' ||
  (SELECT count(*) FROM core.permisos)                           || '|' ||
  (SELECT count(*) FROM core.users WHERE deleted_at IS NULL)     || '|' ||
  (SELECT count(*) FROM core.empresas)                           || '|' ||
  has_function_privilege('erp_veterinary_user',
    'app.sp_auth_login(character varying, text)', 'EXECUTE')::text || '|' ||
  has_table_privilege('erp_veterinary_user', 'core.users', 'SELECT')::text;
SQL
)"
IFS='|' read -r N_SPS N_PERMISOS N_USERS N_EMPRESAS APP_EXEC APP_TABLAS <<<"$RES"

errores=()
(( N_SPS >= 100 ))          || errores+=("solo $N_SPS funciones en app")
(( N_PERMISOS > 0 ))        || errores+=("core.permisos vacía")
[[ "$APP_EXEC" == "true" ]] || errores+=("erp_veterinary_user no puede ejecutar app.sp_auth_login")
[[ "$APP_TABLAS" == "false" ]] || errores+=("erp_veterinary_user puede leer core.users directamente")

if (( ${#errores[@]} )); then
  log "✗ restore-test: la base restaurada no pasa la comprobación: ${errores[*]}"
  exit 1
fi
log "✓ restore-test OK: $N_SPS SPs, $N_PERMISOS permisos, $N_USERS usuarios, $N_EMPRESAS empresas ($(basename "$DUMP"))"
