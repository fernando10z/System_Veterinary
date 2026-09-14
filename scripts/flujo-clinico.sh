#!/usr/bin/env bash
# Flujo clínico completo, de punta a punta, con la empresa independiente
# (Vet Huellitas): cita → consulta → insumo (descuenta stock) → cierre de
# historia → boleta con serie propia → cobro → caja.
#
# Escribe datos reales en la base de demo. Uso:  bash scripts/flujo-clinico.sh
API=http://localhost:3100/api
CACHE="${TMPDIR:-/tmp}/veterp-tokens"
T=$(cat "$CACHE/administracion@vethuellitas.pe" 2>/dev/null) || { echo "Corre antes scripts/verificar-api.sh (deja los tokens en cache)."; exit 1; }
paso() { echo; echo "── $* ──"; }
gets() { curl -s "$API$1" -H "Authorization: Bearer $T"; }
post() { curl -s -X "${3:-POST}" "$API$1" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "$2"; }
# campo <expr-python-sobre-la-lista-o-dict>
campo() { python3 -c "
import json,sys
d=json.load(sys.stdin).get('data')
print($1)
"; }

paso "Contexto"
VET=$(gets /users/veterinarios | campo "d[0]['id']")
MASJ=$(gets /mascotas)
MAS=$(echo "$MASJ" | campo "d[0]['id']")
CLI=$(echo "$MASJ" | campo "d[0].get('cliente_id') or d[0]['cliente']['id']")
SRV=$(gets /catalogos/servicios | campo "d[0]['id']")
PRDJ=$(gets /inventario/productos)
PRD=$(echo "$PRDJ" | campo "d[0]['id']")
STOCK0=$(echo "$PRDJ" | campo "d[0]['stock_actual']")
echo "vet=$VET  mascota=$MAS  cliente=$CLI  servicio=$SRV  producto=$PRD  stock=$STOCK0"

paso "Caja del turno (el efectivo la exige)"
CAJA=$(gets /caja/actual | campo "d.get('id','') if isinstance(d, dict) else ''")
if [[ -z "$CAJA" || "$CAJA" == "None" ]]; then
  R=$(post /caja/abrir '{"monto_apertura":200}')
  CAJA=$(echo "$R" | campo "d['id']")
  echo "caja abierta: $CAJA  ${R:0:120}"
else
  echo "caja ya abierta: $CAJA"
fi

paso "Cita"
CUANDO=$(date -d '+90 minutes' +%FT%H:%M:00)
R=$(post /citas "{\"mascota_id\":\"$MAS\",\"veterinario_id\":\"$VET\",\"fecha_hora\":\"$CUANDO\",\"motivo\":\"  control   POST-operatorio \",\"servicio_id\":\"$SRV\"}")
CITA=$(echo "$R" | campo "d['id']"); echo "cita=$CITA  ${R:0:120}"

paso "Consulta"
R=$(post /clinico/consultas "{\"mascota_id\":\"$MAS\",\"cita_id\":\"$CITA\",\"veterinario_id\":\"$VET\",\"motivo\":\"Control\",\"anamnesis\":\"Sin novedades\",\"peso_kg\":12.4,\"temperatura_c\":38.5}")
CONS=$(echo "$R" | campo "d['id']"); echo "consulta=$CONS  ${R:0:120}"

paso "Insumo — debe descontar stock"
post /clinico/insumos "{\"consulta_id\":\"$CONS\",\"producto_id\":\"$PRD\",\"cantidad\":1}" | head -c 160; echo
STOCK1=$(gets /inventario/productos | campo "[p['stock_actual'] for p in d if p['id']=='$PRD'][0]")
echo "stock: $STOCK0 → $STOCK1"

paso "Orden de servicio y cierre"
post /clinico/ordenes-servicio "{\"mascota_id\":\"$MAS\",\"consulta_id\":\"$CONS\",\"servicio_id\":\"$SRV\",\"cantidad\":1}" | head -c 160; echo
# El diagnóstico se registra actualizando la consulta; cerrar solo la firma.
post "/clinico/consultas/$CONS" '{"diagnostico":"Herida cicatrizada","plan_terapeutico":"Alta médica"}' PATCH | head -c 160; echo
post "/clinico/consultas/$CONS/cerrar" '{}' PATCH | head -c 160; echo

paso "Pendiente de facturar"
PEND=$(gets "/clinico/pendiente-facturar/$CLI"); echo "${PEND:0:300}"

paso "Boleta"
ITEMS=$(echo "$PEND" | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
items=d if isinstance(d,list) else (d.get('items') or [])
print(json.dumps([{
  'tipo': i.get('tipo','servicio'),
  'referencia_id': i['id'],
  'descripcion': i.get('descripcion') or i.get('nombre',''),
  'cantidad': float(i.get('cantidad',1)),
  'precio_unitario': float(i.get('precio_unitario') or i.get('precio') or 0),
} for i in items]))")
echo "items=${ITEMS:0:200}"
R=$(post /facturacion "{\"cliente_id\":\"$CLI\",\"tipo\":\"boleta\",\"items\":$ITEMS}")
COMP=$(echo "$R" | campo "d['id']"); echo "comprobante=$COMP  ${R:0:200}"

paso "Cobro"
if [[ -n "$COMP" ]]; then
  DOC=$(gets "/facturacion/$COMP")
  TOTAL=$(echo "$DOC" | campo "d['total']")
  post /pagos "{\"cliente_id\":\"$CLI\",\"metodo\":\"efectivo\",\"monto\":$TOTAL,\"aplicaciones\":[{\"comprobante_id\":\"$COMP\",\"monto\":$TOTAL}]}" | head -c 200; echo
  gets "/facturacion/$COMP" | campo "(d['serie'], d['numero'], d['estado_pago'], d['total'])"
fi

paso "Caja"
gets /caja/actual | campo "(d.get('numero'), d.get('estado'), d.get('ingresos'), d.get('efectivo'))"

paso "Historia clínica del paciente"
gets "/mascotas/$MAS/historia" | campo "len(d if isinstance(d,list) else d.get('items',[]))"
