#!/usr/bin/env bash
# =============================================================================
# backup.sh — Respaldo de la base (pg_dump -Fc) y, opcionalmente, de los
# archivos clínicos de MinIO, con retención, cifrado y copia fuera del
# servidor.
#
# Conexión: ver _conexion.sh (DB_NAME + DB_CONTAINER o DB_HOST; sin defaults
# de desarrollo silenciosos). Todas las variables pueden ir en
# /etc/veterp/backup.env.
#
# Opciones:
#   BACKUP_DIR              dónde se guardan (db/backups/ por defecto)
#   BACKUP_RETENTION_DAYS   días que se conservan los dumps locales (14)
#   BACKUP_GPG_RECIPIENT    cifra el dump con la clave pública indicada
#   BACKUP_PASSPHRASE_FILE  …o cifrado simétrico con la frase de ese archivo
#   BACKUP_RCLONE_REMOTE    copia fuera del servidor con rclone (remoto:ruta)
#   BACKUP_S3_URI           …o con `aws s3 cp` (s3://bucket/ruta)
#   BACKUP_ALERT_CMD        comando que se ejecuta si el backup falla
#                           (recibe el mensaje en $1), p. ej. un curl a un webhook
#   MINIO_BACKUP=1          además hace `mc mirror` del bucket a BACKUP_DIR/minio
#     MINIO_URL             http://minio:9000
#     MINIO_ACCESS_KEY / MINIO_SECRET_KEY   (basta con el usuario de la app)
#     MINIO_BUCKET          vet-docs
#     MINIO_DOCKER_NETWORK  red del compose si MinIO no publica puerto
#                           (veterp-prod_default): mc corre en un contenedor
#
# Sale con código distinto de 0 y deja constancia en BACKUP_DIR/backup.log
# ante cualquier fallo: un cron que "respalda" en silencio sin respaldar es
# peor que no tener cron.
#
#   DB_CONTAINER=veterp-prod-postgres-1 DB_NAME=veterp bash db/scripts/backup.sh
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_conexion.sh"

BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/../backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
mkdir -p "$BACKUP_DIR"
BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd)"
LOG_FILE="$BACKUP_DIR/backup.log"
chmod 700 "$BACKUP_DIR" 2>/dev/null || true
umask 077

fallo() {
  local msg="Backup FALLIDO de $CONEXION_DESC (línea ${1:-?}): ${2:-error}"
  log "✗ $msg"
  # Un dump a medio escribir se borra; uno ya validado se conserva aunque falle
  # un paso posterior (MinIO, copia externa): sigue siendo un backup bueno.
  if [[ "${DUMP_VALIDO:-0}" != "1" && -n "${OUT:-}" && -f "${OUT:-}" ]]; then rm -f "$OUT"; fi
  if [[ -n "${BACKUP_ALERT_CMD:-}" ]]; then
    bash -c "$BACKUP_ALERT_CMD" _ "$msg" || log "  (el comando de alerta también falló)"
  fi
}
trap 'fallo "$LINENO" "$BASH_COMMAND"' ERR

# Un solo backup a la vez: dos crons solapados escribiendo el mismo mirror de
# MinIO no terminan bien.
exec 9>"$BACKUP_DIR/.backup.lock"
if ! flock -n 9; then
  log "✗ Ya hay un backup en curso; se omite este."
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$BACKUP_DIR/${DB_NAME}_${STAMP}.dump"
log "→ Backup de $CONEXION_DESC → $OUT"

# -Fc ya va comprimido (zlib); se puede restaurar por partes con pg_restore.
pg pg_dump -d "$DB_NAME" -Fc > "$OUT"
[[ -s "$OUT" ]] || { fallo "$LINENO" "el dump quedó vacío"; exit 1; }

# Un dump que pg_restore no sabe leer no es un backup.
pg pg_restore --list < "$OUT" > /dev/null
DUMP_VALIDO=1
log "  dump válido ($(du -h "$OUT" | cut -f1))"

if [[ -n "${BACKUP_GPG_RECIPIENT:-}" ]]; then
  gpg --batch --yes --trust-model always -r "$BACKUP_GPG_RECIPIENT" -o "$OUT.gpg" --encrypt "$OUT"
  rm -f "$OUT"; OUT="$OUT.gpg"
  log "  cifrado para $BACKUP_GPG_RECIPIENT"
elif [[ -n "${BACKUP_PASSPHRASE_FILE:-}" ]]; then
  gpg --batch --yes --pinentry-mode loopback --passphrase-file "$BACKUP_PASSPHRASE_FILE" \
      --symmetric --cipher-algo AES256 -o "$OUT.gpg" "$OUT"
  rm -f "$OUT"; OUT="$OUT.gpg"
  log "  cifrado simétrico (AES256)"
fi

# ---- Archivos clínicos (MinIO) ------------------------------------------------
if [[ "${MINIO_BACKUP:-0}" == "1" ]]; then
  : "${MINIO_URL:?define MINIO_URL}" "${MINIO_ACCESS_KEY:?define MINIO_ACCESS_KEY}"
  : "${MINIO_SECRET_KEY:?define MINIO_SECRET_KEY}"
  MINIO_BUCKET="${MINIO_BUCKET:-vet-docs}"
  # mc mirror de un bucket completo crea la carpeta del bucket dentro del
  # destino: el resultado queda en BACKUP_DIR/minio/<bucket>/.
  DESTINO_MINIO="$BACKUP_DIR/minio"
  mkdir -p "$DESTINO_MINIO"
  log "→ Espejo de MinIO $MINIO_URL/$MINIO_BUCKET → $DESTINO_MINIO"
  # mirror es incremental: solo baja lo nuevo o cambiado. Sin --remove: un
  # archivo borrado en MinIO sigue en el respaldo.
  if [[ -n "${MINIO_DOCKER_NETWORK:-}" ]] || ! command -v mc >/dev/null 2>&1; then
    docker run --rm --network "${MINIO_DOCKER_NETWORK:-host}" \
      -e MINIO_ACCESS_KEY -e MINIO_SECRET_KEY -e MINIO_URL -e MINIO_BUCKET \
      -v "$DESTINO_MINIO:/respaldo" --user "$(id -u):$(id -g)" -e HOME=/tmp \
      --entrypoint /bin/sh "${MC_IMAGE:-pgsty/mc:RELEASE.2026-09-16T00-00-00Z}" -ec '
        mc alias set origen "$MINIO_URL" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null
        mc mirror --overwrite --quiet "origen/$MINIO_BUCKET" /respaldo'
  else
    export MINIO_ACCESS_KEY MINIO_SECRET_KEY
    MC_CONFIG_DIR="$(mktemp -d)"; trap 'rm -rf "$MC_CONFIG_DIR"' EXIT
    mc --config-dir "$MC_CONFIG_DIR" alias set origen "$MINIO_URL" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null
    mc --config-dir "$MC_CONFIG_DIR" mirror --overwrite --quiet "origen/$MINIO_BUCKET" "$DESTINO_MINIO"
  fi
  log "  MinIO: $(find "$DESTINO_MINIO" -type f | wc -l) archivos, $(du -sh "$DESTINO_MINIO" | cut -f1)"
fi

# ---- Retención ----------------------------------------------------------------
BORRADOS=$(find "$BACKUP_DIR" -maxdepth 1 -type f \
  \( -name "${DB_NAME}_*.dump" -o -name "${DB_NAME}_*.dump.gpg" \) \
  -mtime +"$BACKUP_RETENTION_DAYS" -print -delete | wc -l)
[[ "$BORRADOS" -gt 0 ]] && log "  retención: $BORRADOS dump(s) de más de $BACKUP_RETENTION_DAYS días borrados"

# ---- Copia fuera del servidor ---------------------------------------------------
# Un backup que vive en el mismo disco que la base se pierde con él.
if [[ -n "${BACKUP_RCLONE_REMOTE:-}" ]]; then
  rclone copy "$OUT" "$BACKUP_RCLONE_REMOTE/db/"
  [[ "${MINIO_BACKUP:-0}" == "1" ]] && rclone copy "$BACKUP_DIR/minio" "$BACKUP_RCLONE_REMOTE/minio/"
  log "  copiado a $BACKUP_RCLONE_REMOTE"
elif [[ -n "${BACKUP_S3_URI:-}" ]]; then
  aws s3 cp "$OUT" "${BACKUP_S3_URI%/}/db/$(basename "$OUT")"
  [[ "${MINIO_BACKUP:-0}" == "1" ]] && aws s3 sync "$BACKUP_DIR/minio" "${BACKUP_S3_URI%/}/minio/"
  log "  copiado a $BACKUP_S3_URI"
else
  log "  ⚠ sin copia fuera del servidor (BACKUP_RCLONE_REMOTE / BACKUP_S3_URI)"
fi

log "✓ Backup en $OUT"
echo "$OUT"
