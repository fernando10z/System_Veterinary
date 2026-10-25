#!/usr/bin/env bash
# =============================================================================
# crear-superadmin.sh — Crea el PRIMER super administrador de una instalación.
#
# Las migraciones ya no crean usuarios (ver 98_seeds_base.sql): en producción
# la primera cuenta se crea con este script, con una clave que solo conoce
# quien lo ejecuta. La cuenta nace con `must_change_password`: la clave que se
# teclea aquí sirve para entrar una vez y cambiarla.
#
# No reescribe nada: si el correo ya existe, se detiene sin tocar su clave.
#
# Datos por entorno o, si falta alguno y hay terminal, se piden en pantalla
# (la contraseña sin eco):
#   SUPERADMIN_EMAIL  SUPERADMIN_PASSWORD  SUPERADMIN_NOMBRES
#   SUPERADMIN_APELLIDO  SUPERADMIN_DNI
#
# Conexión: las mismas variables que apply-migrations.sh (DB_HOST, DB_PORT,
# DB_USER, DB_PASSWORD, DB_NAME, DB_CONTAINER). Necesita psql >= 15.
#
# Uso:
#   DB_HOST=localhost DB_PORT=5432 DB_NAME=veterp DB_PASSWORD=… \
#     bash db/scripts/crear-superadmin.sh
#   # con el compose de producción:
#   docker compose -f infra/docker/docker-compose.prod.yml run --rm migrate \
#     bash /db/scripts/crear-superadmin.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_psql.sh"

pedir() {  # pedir VAR "Etiqueta" [secreto]
  local var="$1" etiqueta="$2" secreto="${3:-}" valor=""
  if [[ -n "${!var:-}" ]]; then return; fi
  if [[ ! -t 0 ]]; then
    echo "✗ Falta $var y no hay terminal para pedirlo." >&2
    exit 1
  fi
  if [[ -n "$secreto" ]]; then
    read -rsp "$etiqueta: " valor; echo
    local repetido
    read -rsp "Repite la contraseña: " repetido; echo
    [[ "$valor" == "$repetido" ]] || { echo "✗ Las contraseñas no coinciden." >&2; exit 1; }
  else
    read -rp "$etiqueta: " valor
  fi
  printf -v "$var" '%s' "$valor"
}

pedir SUPERADMIN_EMAIL    "Correo"
pedir SUPERADMIN_NOMBRES  "Nombres"
pedir SUPERADMIN_APELLIDO "Apellido paterno"
pedir SUPERADMIN_DNI      "DNI"
pedir SUPERADMIN_PASSWORD "Contraseña inicial" secreto

export SUPERADMIN_EMAIL SUPERADMIN_PASSWORD SUPERADMIN_NOMBRES SUPERADMIN_APELLIDO SUPERADMIN_DNI
PSQL_DOCKER_ENV=(-e SUPERADMIN_EMAIL -e SUPERADMIN_PASSWORD -e SUPERADMIN_NOMBRES
                 -e SUPERADMIN_APELLIDO -e SUPERADMIN_DNI)

echo "→ Creando super admin en $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"

# Los datos entran por \getenv y se pasan al bloque con set_config(..., true):
# duran lo que la transacción y nunca aparecen en la línea de comandos ni
# interpolados en el SQL.
run_psql --single-transaction <<'SQL'
\getenv sa_email    SUPERADMIN_EMAIL
\getenv sa_pwd      SUPERADMIN_PASSWORD
\getenv sa_nombres  SUPERADMIN_NOMBRES
\getenv sa_apellido SUPERADMIN_APELLIDO
\getenv sa_dni      SUPERADMIN_DNI
SELECT set_config('veterp.sa_email',    :'sa_email',    true),
       set_config('veterp.sa_pwd',      :'sa_pwd',      true),
       set_config('veterp.sa_nombres',  :'sa_nombres',  true),
       set_config('veterp.sa_apellido', :'sa_apellido', true),
       set_config('veterp.sa_dni',      :'sa_dni',      true) \g /dev/null

DO $$
DECLARE
  v_email  TEXT := lower(trim(current_setting('veterp.sa_email')));
  v_pwd    TEXT := current_setting('veterp.sa_pwd');
  v_rol    UUID;
  v_motivo TEXT;
BEGIN
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'El correo "%" no es válido', v_email;
  END IF;

  IF EXISTS (SELECT 1 FROM core.users WHERE lower(email) = v_email) THEN
    RAISE EXCEPTION 'Ya existe un usuario con el correo %. No se modifica: para recuperar el acceso usa el reset de contraseña.', v_email;
  END IF;

  v_motivo := internal.password_invalida(v_pwd, v_email);
  IF v_motivo IS NOT NULL THEN
    RAISE EXCEPTION '%', v_motivo;
  END IF;

  SELECT id INTO v_rol FROM core.roles WHERE codigo = 'super_admin';
  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'No existe el rol super_admin: aplica antes las migraciones';
  END IF;

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno,
    tipo_documento, numero_documento, empresa_id, is_super_admin, rol_id,
    estado, must_change_password)
  VALUES (
    internal.siguiente_numero('00000000-0000-0000-0000-000000000000'::uuid, 'USR', 4),
    v_email, crypt(v_pwd, gen_salt('bf', 10)),
    trim(current_setting('veterp.sa_nombres')),
    trim(current_setting('veterp.sa_apellido')),
    'DNI', trim(current_setting('veterp.sa_dni')),
    NULL, true, v_rol, 'activo', true);

  RAISE NOTICE 'Super admin % creado. Deberá cambiar la contraseña al entrar.', v_email;
END $$;
SQL

echo "✓ Listo. Entra con $SUPERADMIN_EMAIL: el sistema pedirá cambiar la contraseña."
