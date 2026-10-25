#!/usr/bin/env bash
#
# deploy.sh — publica el ERP Veterinary con releases inmutables + symlink `current`.
#
#   deploy.sh               backend + frontend
#   deploy.sh backend       solo backend (el frontend sigue igual)
#   deploy.sh frontend      solo frontend (sin reiniciar nada)
#   deploy.sh rollback      vuelve al release anterior
#   deploy.sh activar <rel> activa un release concreto (p. ej. volver hacia adelante)
#   deploy.sh list          lista releases (el activo con *)
#
# Estructura (APP_ROOT se deduce de la ubicación de este script):
#   $APP_ROOT/src/                  repo git: aquí se edita
#   $APP_ROOT/releases/<fecha>-<sha>/{backend,frontend}
#   $APP_ROOT/current -> releases/…  lo que corre pm2
#   $APP_ROOT/shared/backend.env     secretos (fuera de git y de los releases)
#
# Ojo: el rollback regresa CÓDIGO, no la base de datos. Las migraciones van
# siempre hacia adelante y compatibles con el release anterior (expand/contract).
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
APP_ROOT="$(dirname "$SRC")"
RELEASES="$APP_ROOT/releases"
CURRENT="$APP_ROOT/current"
SHARED="$APP_ROOT/shared"
KEEP="${KEEP:-5}"
ASSETS_DIAS="${ASSETS_DIAS:-14}"

# Nombres pm2 y puertos: salen del ecosystem del propio repo.
ECOSYSTEM="$SRC/infra/pm2/ecosystem.config.js"
API_NAME="$(node -e "console.log(require('$ECOSYSTEM').apps[0].name)")"
API_URL="${API_URL:-http://127.0.0.1:3200/api/health}"
WEB_URL="${WEB_URL:-http://127.0.0.1:5373/index.html}"

c_ok() { printf '\033[32m%s\033[0m\n' "$*"; }
c_info() { printf '\033[36m» %s\033[0m\n' "$*"; }
c_err() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; }

exec 9>"$APP_ROOT/.deploy.lock"
flock -n 9 || { c_err "Hay otro deploy en curso."; exit 1; }

activo() { [[ -L "$CURRENT" ]] && basename "$(readlink -f "$CURRENT")" || true; }

apuntar() { # cambio atómico del symlink
  ln -sfn "$1" "$APP_ROOT/.current.tmp"
  mv -T "$APP_ROOT/.current.tmp" "$CURRENT"
}

esperar_200() { # url, segundos
  local url="$1" t="${2:-40}"
  for ((i = 0; i < t; i++)); do
    [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url")" == 200 ]] && return 0
    sleep 1
  done
  return 1
}

salud() {
  esperar_200 "$API_URL" 45 || { c_err "API no responde 200 en $API_URL"; return 1; }
  esperar_200 "$WEB_URL" 15 || { c_err "Web no responde 200 en $WEB_URL"; return 1; }
}

listar() {
  local act; act="$(activo)"
  ls -1 "$RELEASES" 2>/dev/null | sort | while read -r r; do
    [[ "$r" == "$act" ]] && echo "* $r" || echo "  $r"
  done
}

activar() { # activa un release existente (rollback o volver hacia adelante)
  local act destino="$1"
  act="$(activo)"
  [[ -d "$RELEASES/$destino" ]] || { c_err "No existe el release $destino."; listar; exit 1; }
  c_info "$act → $destino"
  apuntar "$RELEASES/$destino"
  pm2 reload "$API_NAME" --update-env >/dev/null
  salud && c_ok "Activo: $destino (recuerda: la BD no cambia de versión)."
}

rollback() {
  local act prev
  act="$(activo)"
  prev="$(ls -1 "$RELEASES" | sort | grep -B1 -x "$act" | head -1)"
  [[ -n "$prev" && "$prev" != "$act" ]] || { c_err "No hay release anterior a $act."; exit 1; }
  activar "$prev"
}

podar() {
  local act; act="$(activo)"
  ls -1 "$RELEASES" | sort | head -n -"$KEEP" | while read -r r; do
    [[ "$r" == "$act" ]] || rm -rf "${RELEASES:?}/$r"
  done
}

desplegar() {
  local que="$1" sha nuevo prev
  cd "$SRC"
  sha="$(git rev-parse --short HEAD)"
  git diff --quiet HEAD -- backend frontend || {
    sha="$sha-dirty"
    c_info "Hay cambios sin commit en backend/frontend: el release se marca -dirty."
  }
  nuevo="$RELEASES/$(date +%Y%m%d-%H%M%S)-$sha"
  prev="$(readlink -f "$CURRENT" 2>/dev/null || true)"

  if [[ "$que" != frontend ]]; then
    c_info "Compilando backend…"
    (cd "$SRC/backend" && npm run build --silent)
  fi
  if [[ "$que" != backend ]]; then
    c_info "Compilando frontend…"
    (cd "$SRC/frontend" && npm run build --silent)
  fi

  mkdir -p "$nuevo"
  if [[ "$que" == frontend && -d "$prev/backend" ]]; then
    cp -a "$prev/backend" "$nuevo/backend"
  else
    mkdir -p "$nuevo/backend"
    cp -a "$SRC/backend/dist" "$SRC/backend/package.json" "$SRC/backend/node_modules" "$nuevo/backend/"
    ln -s "$SHARED/backend.env" "$nuevo/backend/.env"
  fi

  if [[ "$que" == backend && -d "$prev/frontend" ]]; then
    cp -a "$prev/frontend" "$nuevo/frontend"
  else
    cp -a "$SRC/frontend/dist" "$nuevo/frontend"
    # Las pestañas abiertas piden los assets del build anterior (nombres con hash):
    # se conservan unos días para que no se vean "sin estilos".
    if [[ -d "$prev/frontend/assets" ]]; then
      cp -a --update=none "$prev/frontend/assets/." "$nuevo/frontend/assets/"
      find "$nuevo/frontend/assets" -type f -mtime +"$ASSETS_DIAS" -delete
    fi
  fi

  apuntar "$nuevo"
  if [[ "$que" != frontend ]]; then
    pm2 reload "$API_NAME" --update-env >/dev/null
  fi

  if salud; then
    podar
    c_ok "Desplegado $(basename "$nuevo") ($que)."
  else
    c_err "Falló la verificación: vuelvo al release anterior."
    if [[ -n "$prev" ]]; then
      apuntar "$prev"
      pm2 reload "$API_NAME" --update-env >/dev/null
      salud && c_ok "Restaurado $(basename "$prev")."
    fi
    exit 1
  fi
}

mkdir -p "$RELEASES"
case "${1:-all}" in
  all | backend | frontend) desplegar "${1:-all}" ;;
  rollback) rollback ;;
  activar) activar "${2:?uso: deploy.sh activar <release>}" ;;
  list) listar ;;
  *) echo "uso: $(basename "$0") [all|backend|frontend|rollback|activar <release>|list]"; exit 2 ;;
esac
