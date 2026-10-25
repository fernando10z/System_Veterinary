#!/usr/bin/env bash
# =============================================================================
# restore.sh — Restaura un dump de backup.sh sobre la base indicada.
#
#   DB_CONTAINER=veterp-prod-postgres-1 DB_NAME=veterp \
#     bash db/scripts/restore.sh db/backups/veterp_20260822_101500.dump
#
# Acepta .dump y .dump.gpg (se descifra con gpg: clave privada en el llavero o
# BACKUP_PASSPHRASE_FILE). Conexión: ver _conexion.sh.
#
# --clean --if-exists: elimina los objetos existentes antes de recrearlos, así
# que SOBRESCRIBE la base de destino. Pide confirmación salvo FORCE=1. La base
# tiene que existir (restore-test.sh crea la suya).
#
# El dump se restaura sin dueños ni permisos (--no-owner --no-privileges): al
# terminar se vuelve a aplicar 90_grants.sql, que rehace erp_veterinary_user, su
# EXECUTE sobre app.* y la revocación a PUBLIC. Sin ese paso el backend no
# podría llamar a ningún SP de la base restaurada. Con VET_APP_PASSWORD, además
# se fija la contraseña del rol.
# =============================================================================
set -Eeuo pipefail

DUMP="${1:-}"
[[ -f "$DUMP" ]] || { echo "✗ Uso: restore.sh <archivo.dump|archivo.dump.gpg>" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_conexion.sh"
trap 'echo "✗ Restauración FALLIDA en la línea $LINENO: $BASH_COMMAND" >&2' ERR

echo "→ Restaurar $DUMP sobre $CONEXION_DESC (se sobrescriben los objetos existentes)"
if [[ "${FORCE:-0}" != "1" ]]; then
  read -rp "Escribe el nombre de la base para confirmar: " r
  [[ "$r" == "$DB_NAME" ]] || { echo "Cancelado."; exit 1; }
fi

# Fuente del dump: descifrado al vuelo si viene cifrado.
leer_dump() {
  case "$DUMP" in
    *.gpg)
      if [[ -n "${BACKUP_PASSPHRASE_FILE:-}" ]]; then
        gpg --batch --quiet --pinentry-mode loopback --passphrase-file "$BACKUP_PASSPHRASE_FILE" -d "$DUMP"
      else
        gpg --batch --quiet -d "$DUMP"
      fi ;;
    *) cat "$DUMP" ;;
  esac
}

# pg_restore desde stdin: funciona igual con el binario del host o dentro del
# contenedor. --exit-on-error: una restauración a medias no se da por buena.
leer_dump | pg pg_restore -d "$DB_NAME" --clean --if-exists --no-owner --no-privileges --exit-on-error

echo "→ Rol de aplicación y permisos (90_grants.sql)"
pg psql -d "$DB_NAME" -v ON_ERROR_STOP=1 --quiet --no-psqlrc \
  < "$SCRIPT_DIR/../migrations/90_grants.sql" > /dev/null

if [[ -n "${VET_APP_PASSWORD:-}" ]]; then
  export VET_APP_PASSWORD
  if [[ -n "${DB_CONTAINER:-}" ]]; then
    docker exec -i -e VET_APP_PASSWORD ${PGPASSWORD:+-e PGPASSWORD} "$DB_CONTAINER" \
      psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 --quiet --no-psqlrc > /dev/null <<'SQL'
\getenv app_pwd VET_APP_PASSWORD
ALTER ROLE erp_veterinary_user WITH LOGIN PASSWORD :'app_pwd';
SQL
  else
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
      --quiet --no-psqlrc > /dev/null <<'SQL'
\getenv app_pwd VET_APP_PASSWORD
ALTER ROLE erp_veterinary_user WITH LOGIN PASSWORD :'app_pwd';
SQL
  fi
  echo "  contraseña de erp_veterinary_user fijada"
fi

echo "✓ Restaurado $DUMP en $CONEXION_DESC"
echo "  Las sesiones abiertas (Redis) siguen vigentes: si la restauración revierte"
echo "  cambios de usuarios, conviene reiniciar Redis o esperar a que expiren."
