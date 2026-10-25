#!/usr/bin/env bash
# =============================================================================
# verificar-concurrencia.sh — lo que pasa cuando dos personas pulsan a la vez
#
# verificar-api.sh hace una llamada cada vez, y así nunca iba a ver una
# carrera: dos cajeros que emiten la boleta del mismo propietario, dos ventas
# del último frasco, dos cobros sobre el mismo saldo. Aquí cada prueba prepara
# su escenario y dispara N llamadas simultáneas al mismo SP, cada una en su
# propia conexión. Después cuenta: exactamente una tiene que ganar.
#
# Habla directo con la base (las carreras se resuelven ahí, no en la API).
#
#   bash scripts/verificar-concurrencia.sh
#   DB_NAME=vet_demo N=8 bash scripts/verificar-concurrencia.sh
# =============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../db/scripts/_psql.sh
source "$RAIZ/db/scripts/_psql.sh"

N="${N:-6}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OK=0; FALLOS=0
q() { run_psql -At -c "$1"; }

bien() { echo "  ✓ $1"; OK=$((OK + 1)); }
mal()  { echo "  ✗ $1"; FALLOS=$((FALLOS + 1)); }

# Dispara N copias de la misma sentencia a la vez; deja cada respuesta en un
# archivo y devuelve cuántas respondieron {"ok": true}.
en_paralelo() {
  local nombre="$1" sql="$2" i
  for i in $(seq 1 "$N"); do
    q "${sql//__I__/$i}" > "$TMP/$nombre.$i" 2>&1 &
  done
  wait
  grep -l '"ok": true' "$TMP/$nombre".* 2>/dev/null | wc -l | tr -d ' '
}

esperar() { # esperar <descripción> <esperado> <obtenido>
  if [[ "$2" == "$3" ]]; then bien "$1 ($3)"; else mal "$1: se esperaba $2, salió $3"; fi
}

TAG="$(date +%s)$RANDOM"
dni() { printf '%08d' $(( (RANDOM * 32768 + RANDOM) % 100000000 )); }

IFS='|' read -r U E <<< "$(q "SELECT id, empresa_id FROM core.users WHERE email = 'administracion@vetpatitas.pe'")"
VET="$(q "SELECT id FROM core.users WHERE email = 'jperez@vetpatitas.pe'")"
ESPECIE="$(q "SELECT id FROM core.especies ORDER BY nombre LIMIT 1")"
if [[ -z "${U:-}" || -z "${VET:-}" ]]; then
  echo "✗ No están los usuarios de demostración. Aplica las migraciones con SEED_DEMO=1." >&2
  exit 1
fi

sp() { # sp <función> <payload-sql> → id de data
  q "SELECT app.$1('$U','$E',false, $2)->'data'->>'id'"
}

nuevo_cliente() {
  sp sp_cliente_crear "jsonb_build_object('tipo_documento','DNI','numero_documento','$(dni)',
    'nombres','Carrera $TAG','apellido_paterno','Prueba')"
}

nueva_mascota() { # nueva_mascota <cliente>
  sp sp_mascota_crear "jsonb_build_object('cliente_id','$1','nombre','Rayo $TAG','especie_id','$ESPECIE')"
}

item() { # item <descripción> <precio> [extra-jsonb]
  echo "jsonb_build_object('descripcion','$1','cantidad',1,'precio_unitario',$2)${3:+ || $3}"
}

echo "═══ Concurrencia: $N llamadas simultáneas por prueba ═══"

# -----------------------------------------------------------------------------
echo "── 1. El último frasco se vende una sola vez"
PROD="$(sp sp_producto_guardar "jsonb_build_object('nombre','Frasco $TAG','precio_venta',10)")"
q "SELECT app.sp_inventario_movimiento('$U','$E',false, jsonb_build_object(
     'producto_id','$PROD','tipo','entrada','motivo','compra','cantidad',1))" > /dev/null
CLI="$(nuevo_cliente)"
GANAN=$(en_paralelo stock "SELECT app.sp_comprobante_emitir('$U','$E',false, jsonb_build_object(
  'cliente_id','$CLI','tipo','nota_venta','items', jsonb_build_array(
    $(item 'Frasco' 10 "jsonb_build_object('producto_id','$PROD')"))))")
esperar "ventas que salieron" 1 "$GANAN"
esperar "stock final" "0.00" "$(q "SELECT stock_actual FROM core.productos WHERE id = '$PROD'")"

# -----------------------------------------------------------------------------
echo "── 2. La misma consulta no sale en dos boletas"
CLI="$(nuevo_cliente)"; MAS="$(nueva_mascota "$CLI")"
SRV="$(q "SELECT id FROM core.servicios WHERE empresa_id = '$E' AND deleted_at IS NULL AND precio > 0 ORDER BY codigo LIMIT 1")"
OS="$(sp sp_orden_servicio_crear "jsonb_build_object('mascota_id','$MAS','servicio_id','$SRV','estado','completado')")"
GANAN=$(en_paralelo cobro_doble "SELECT app.sp_comprobante_emitir('$U','$E',false,
  jsonb_build_object('cliente_id','$CLI','tipo','nota_venta'))")
esperar "emisiones que tomaron lo pendiente" 1 "$GANAN"
esperar "veces que la orden quedó facturada" 1 \
  "$(q "SELECT count(*) FROM core.comprobante_items WHERE orden_servicio_id = '$OS'")"

# -----------------------------------------------------------------------------
echo "── 3. Dos cobros no se comen el mismo saldo"
CLI="$(nuevo_cliente)"
BOL="$(sp sp_comprobante_emitir "jsonb_build_object('cliente_id','$CLI','tipo','boleta',
  'items', jsonb_build_array($(item 'Cirugía' 100)))")"
GANAN=$(en_paralelo sobrecobro "SELECT app.sp_pago_registrar('$U','$E',false, jsonb_build_object(
  'cliente_id','$CLI','monto',60,'metodo','yape','referencia','$TAG-__I__',
  'aplicaciones', jsonb_build_array(jsonb_build_object('comprobante_id','$BOL','monto',60))))")
esperar "cobros de 60 sobre una deuda de 100" 1 "$GANAN"
esperar "saldo final" "40.00" "$(q "SELECT saldo_pendiente FROM core.comprobantes WHERE id = '$BOL'")"

# -----------------------------------------------------------------------------
echo "── 4. Una boleta no se acredita dos veces"
CLI="$(nuevo_cliente)"
BOL="$(sp sp_comprobante_emitir "jsonb_build_object('cliente_id','$CLI','tipo','boleta',
  'items', jsonb_build_array($(item 'Vacuna' 50)))")"
GANAN=$(en_paralelo nc "SELECT app.sp_nota_credito_emitir('$U','$E',false,
  jsonb_build_object('comprobante_id','$BOL','motivo','Devolución total'))")
esperar "notas de crédito totales" 1 "$GANAN"
esperar "total acreditado" "50.00" "$(q "SELECT COALESCE(SUM(total),0) FROM core.comprobantes
  WHERE documento_ref_id = '$BOL' AND anulado_at IS NULL")"
esperar "saldo de la boleta" "0.00" "$(q "SELECT saldo_pendiente FROM core.comprobantes WHERE id = '$BOL'")"

# -----------------------------------------------------------------------------
echo "── 5. El mismo hueco de agenda no se reserva dos veces"
CLI="$(nuevo_cliente)"; MAS="$(nueva_mascota "$CLI")"
HORA="$(q "SELECT to_char(date_trunc('hour', now() + interval '20 days') + (random()*8)::int * interval '1 hour', 'YYYY-MM-DD\"T\"HH24:MI:SSOF')")"
GANAN=$(en_paralelo agenda "SELECT app.sp_cita_crear('$U','$E',false, jsonb_build_object(
  'mascota_id','$MAS','veterinario_id','$VET','fecha_hora','$HORA','duracion_min',30,'motivo','Control'))")
esperar "citas en el mismo horario" 1 "$GANAN"

# -----------------------------------------------------------------------------
echo "── 6. Un doble clic en «Emitir» numera un solo comprobante"
CLI="$(nuevo_cliente)"
KEY="$(q "SELECT gen_random_uuid()")"
GANAN=$(en_paralelo idem "SELECT app.sp_comprobante_emitir('$U','$E',false, jsonb_build_object(
  'cliente_id','$CLI','tipo','boleta','idempotency_key','$KEY',
  'items', jsonb_build_array($(item 'Baño' 35))))")
esperar "respuestas correctas (la misma boleta)" "$N" "$GANAN"
esperar "boletas numeradas" 1 "$(q "SELECT count(*) FROM core.comprobantes WHERE idempotency_key = '$KEY'")"

# -----------------------------------------------------------------------------
echo "── 7. El cupo del plan no se desborda"
CLI="$(nuevo_cliente)"; MAS="$(nueva_mascota "$CLI")"
PLAN="$(sp sp_plan_guardar "jsonb_build_object('nombre','Plan carrera $TAG','precio',0,
  'vigencia_meses',12,'beneficios', jsonb_build_array(jsonb_build_object(
    'tipo','servicio_incluido','servicio_id','$SRV','cantidad',1)))")"
sp sp_suscripcion_crear "jsonb_build_object('plan_id','$PLAN','mascota_id','$MAS')" > /dev/null
en_paralelo cupo "SELECT app.sp_orden_servicio_crear('$U','$E',false, jsonb_build_object(
  'mascota_id','$MAS','servicio_id','$SRV','estado','completado'))" > /dev/null
esperar "órdenes cubiertas por un cupo de 1" 1 \
  "$(q "SELECT count(*) FROM core.ordenes_servicio WHERE mascota_id = '$MAS' AND cubierto_por_plan")"

echo
echo "═══════════════════════════════════════"
echo "  OK: $OK    FALLOS: $FALLOS"
[[ "$FALLOS" -eq 0 ]]
