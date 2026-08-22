#!/usr/bin/env bash
# =============================================================================
# reset-dev.sh — DESTRUYE y recrea el schema de desarrollo desde cero.
# Requiere ALLOW_RESET=yes explícito: nunca debe correr por accidente.
#
#   ALLOW_RESET=yes bash db/scripts/reset-dev.sh
# =============================================================================
set -euo pipefail

if [[ "${ALLOW_RESET:-no}" != "yes" ]]; then
  echo "✗ Refuse: exporta ALLOW_RESET=yes para confirmar el borrado total." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_psql.sh"

if [[ "$DB_NAME" != *demo* && "$DB_NAME" != *dev* && "$DB_NAME" != *test* ]]; then
  echo "✗ Refuse: '$DB_NAME' no parece una BD de desarrollo." >&2
  exit 1
fi

echo "→ Borrando schemas de $DB_NAME…"
run_psql -c "DROP SCHEMA IF EXISTS app CASCADE; DROP SCHEMA IF EXISTS internal CASCADE; DROP SCHEMA IF EXISTS core CASCADE; DROP SCHEMA IF EXISTS audit CASCADE;" > /dev/null

bash "$SCRIPT_DIR/apply-migrations.sh"
echo "✓ Base de desarrollo reconstruida."
