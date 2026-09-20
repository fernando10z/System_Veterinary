#!/usr/bin/env bash
# =============================================================================
# Verificación funcional y de aislamiento del ERP veterinario.
#
# Cubre: login de las dos empresas, las rutas GET con ambas, intentos de
# lectura y escritura cruzada entre empresas, escalada de privilegios,
# normalización del dato, razas propias por empresa, aislamiento de los
# documentos clínicos imprimibles y de la sala de espera.
#
# Requiere el backend levantado en :3100 y la base con los seeds de demo.
# Uso:  bash scripts/verificar-api.sh
#
# El login tiene límite anti-fuerza-bruta (10/min); el script cachea los tokens
# y espera la ventana si la topa.
# =============================================================================
API=http://localhost:3100/api
CACHE="${TMPDIR:-/tmp}/veterp-tokens"
mkdir -p "$CACHE"
ok=0; fail=0
declare -a FALLOS

# login <email> → token. Cachea en disco para no gastar la cuota de 10/min.
login() {
  local f="$CACHE/$1" t resp code intentos=0
  if [[ -s "$f" ]]; then
    t=$(cat "$f")
    if [[ "$(curl -s -o /dev/null -w '%{http_code}' "$API/auth/perfil" -H "Authorization: Bearer $t")" == 200 ]]; then
      echo "$t"; return
    fi
  fi
  while :; do
    resp=$(curl -s -w '\n%{http_code}' "$API/auth/login" -H 'Content-Type: application/json' \
           -d "{\"email\":\"$1\",\"password\":\"Demo2026!\"}")
    code=$(tail -1 <<<"$resp")
    [[ "$code" != 429 || $intentos -ge 3 ]] && break
    echo "  · $1: rate-limit, esperando la ventana…" >&2
    sleep 62; intentos=$((intentos+1))
  done
  t=$(head -n -1 <<<"$resp" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("data",{}).get("access_token",""))' 2>/dev/null)
  [[ -n "$t" ]] && printf '%s' "$t" > "$f"
  echo "$t"
}

get() { curl -s -o /tmp/vbody -w '%{http_code}' "$API$2" -H "Authorization: Bearer $1"; }
req() { curl -s -o /tmp/vbody -w '%{http_code}' -X "$3" "$API$2" -H "Authorization: Bearer $1" \
        -H 'Content-Type: application/json' -d "${4:-{\}}"; }

# jid → primer id del cuerpo, sea lista, {items:[]} u objeto.
jid() {
  python3 <<'PYX'
import json
d = json.load(open("/tmp/vbody")).get("data")
if isinstance(d, dict) and not d.get("id"):
    d = d.get("items") or d.get("data") or d
print((d[0]["id"] if d else "") if isinstance(d, list) else d.get("id", ""))
PYX
}

check() {
  if [[ "$2" == "$3" ]]; then ok=$((ok+1))
  else fail=$((fail+1)); FALLOS+=("$1 → esperaba $2, obtuvo $3 :: $(head -c 220 /tmp/vbody)"); fi
}

echo "═══ 1. Autenticación ═══"
T_SUPER=$(login admin@vetpatitas.pe)
T_E1=$(login administracion@vetpatitas.pe)
T_E2=$(login administracion@vethuellitas.pe)
T_VET2=$(login dvaldez@vethuellitas.pe)
for n in T_SUPER T_E1 T_E2 T_VET2; do
  if [[ -n "${!n}" ]]; then ok=$((ok+1)); echo "  ✓ $n"; else fail=$((fail+1)); FALLOS+=("login $n vacío"); echo "  ✗ $n"; fi
done
[[ -z "$T_E2" ]] && { echo "Sin tokens, abortando."; exit 1; }

echo "═══ 2. Lecturas: todas las rutas GET, con las dos empresas ═══"
RUTAS=(
 /auth/perfil /caja /caja/actual /catalogos/categorias /catalogos/clausulas
 /catalogos/consultorios /catalogos/especializaciones /catalogos/especies
 /catalogos/esquemas-vacunacion /catalogos/horarios /catalogos/servicios
 /citas /citas/agenda-dia /citas/sala-espera /citas/lista-espera
 /clientes /clientes/comunicaciones
 /clinico/cirugias /clinico/consultas /clinico/hospitalizaciones
 /compras/ordenes /compras/pagos /compras/proveedores
 /dashboard /dashboard/recordatorios /dashboard/plantillas /empresas/actual
 /facturacion /facturacion/cuentas-por-cobrar /facturacion/sunat/pendientes
 /inventario/alertas /inventario/almacenes /inventario/movimientos /inventario/productos
 /mascotas /mascotas/extraviadas /notificaciones /pagos
 /reportes/clinico /reportes/inventario /reportes/ventas
 /roles /roles/permisos /rrhh/asistencia /rrhh/disponibilidad /rrhh/equipo /rrhh/permisos
 /users /users/veterinarios /auditoria
)
for tok in T_E1 T_E2; do
  n=0
  for r in "${RUTAS[@]}"; do
    c=$(get "${!tok}" "$r"); check "GET $r ($tok)" 200 "$c"
    [[ "$c" == 200 ]] && n=$((n+1)) || echo "    ✗ $r → $c"
  done
  echo "  $tok: $n/${#RUTAS[@]}"
done
c=$(get "$T_SUPER" /empresas);           check "GET /empresas (super)" 200 "$c"
c=$(get "$T_SUPER" /reportes/ejecutivo); check "GET /reportes/ejecutivo (super)" 200 "$c"

echo "═══ 3. Aislamiento de cartera ═══"
get "$T_E1" /clientes >/dev/null; CLI1=$(jid)
get "$T_E1" /mascotas >/dev/null; MAS1=$(jid)
echo "  cliente e1=$CLI1  mascota e1=$MAS1"
for caso in "GET:/clientes/$CLI1:lee cliente" "GET:/mascotas/$MAS1:lee mascota" \
            "GET:/mascotas/$MAS1/historia:lee historia" "GET:/mascotas/$MAS1/vacunas:lee vacunas"; do
  IFS=: read -r m ruta et <<<"$caso"
  c=$(get "$T_E2" "$ruta"); check "e2 $et de e1" 404 "$c"
done
c=$(req "$T_E2" "/clientes/$CLI1" PATCH '{"nombres":"HACKEADO"}'); check "e2 edita cliente de e1" 404 "$c"
c=$(req "$T_E2" "/mascotas/$MAS1" PATCH '{"nombre":"HACKEADO"}');  check "e2 edita mascota de e1" 404 "$c"

echo "═══ 3b. Aislamiento de los documentos imprimibles ═══"
# Un documento clínico lleva nombre, teléfono y dirección del propietario: es
# justo lo que no puede cruzar de una empresa a otra.
get "$T_E1" /clinico/consultas >/dev/null; CONS1=$(jid)
get "$T_E1" /clinico/cirugias  >/dev/null; CIR1=$(jid)
get "$T_E1" /clinico/hospitalizaciones >/dev/null; HOSP1=$(jid)
for caso in "/documentos/carne-vacunacion/$MAS1:carné" \
            "/documentos/historia-clinica/$MAS1:historia" \
            "/documentos/certificado-salud/$MAS1:certificado"; do
  IFS=: read -r ruta et <<<"$caso"
  c=$(get "$T_E2" "$ruta"); check "e2 imprime $et de e1" 404 "$c"
done
[[ -n "$CONS1" ]] && { c=$(get "$T_E2" "/documentos/receta/$CONS1");            check "e2 imprime receta de e1" 404 "$c"; }
[[ -n "$CIR1"  ]] && { c=$(get "$T_E2" "/documentos/consentimiento/$CIR1");      check "e2 imprime consentimiento de e1" 404 "$c"; }
[[ -n "$HOSP1" ]] && { c=$(get "$T_E2" "/documentos/alta-hospitalaria/$HOSP1");  check "e2 imprime alta de e1" 404 "$c"; }
# El propio sí debe poder.
c=$(get "$T_E1" "/documentos/carne-vacunacion/$MAS1"); check "e1 imprime su carné" 200 "$c"

echo "═══ 3c. Sala de espera y cobro ═══"
# Registrar la llegada de un paciente ajeno es meterlo en la agenda de otra
# empresa: tiene que fallar por el mismo camino que el resto.
c=$(req "$T_E2" /citas/llegada POST "{\"mascota_id\":\"$MAS1\"}")
check "e2 registra llegada de paciente de e1" 404 "$c"
c=$(req "$T_E2" /citas/lista-espera POST "{\"mascota_id\":\"$MAS1\",\"desde\":\"$(date +%F)\"}")
check "e2 anota paciente de e1 en lista de espera" 404 "$c"

# Un comprobante de otra empresa no se envía a SUNAT ni se acredita.
get "$T_E1" /facturacion >/dev/null; COMP1=$(jid)
if [[ -n "$COMP1" ]]; then
  # 404 y no 403: la convención del sistema es no revelar que el registro
  # existe en otra empresa.
  c=$(req "$T_E2" "/facturacion/$COMP1/sunat/enviar" POST)
  check "e2 envía a SUNAT comprobante de e1" 404 "$c"
  c=$(req "$T_E2" /facturacion/notas-credito POST \
      "{\"comprobante_id\":\"$COMP1\",\"motivo\":\"Intento de acceso cruzado\"}")
  check "e2 acredita comprobante de e1" 404 "$c"
fi

echo "═══ 4. Escalada de privilegios ═══"
get "$T_E1" /users >/dev/null;        U1=$(jid)
# El id propio sale del JWT: /auth/perfil devuelve el perfil anidado.
ME2=$(python3 - "$T_E2" <<'PYX'
import base64, json, sys
p = sys.argv[1].split(".")[1]
print(json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))["sub"])
PYX
)
get "$T_SUPER" /roles >/dev/null
ROL_SUPER=$(python3 <<'PYX'
import json
d = json.load(open("/tmp/vbody")).get("data")
if isinstance(d, dict): d = d.get("items", [])
print(next((r["id"] for r in d if r.get("codigo") == "super_admin"), ""))
PYX
)
echo "  user e1=$U1  yo(e2)=$ME2  rol super_admin=$ROL_SUPER"
c=$(req "$T_E2" "/users/$U1/reset-password" POST '{"password_temp":"Temporal2026!"}'); check "e2 resetea clave de user e1" 404 "$c"
c=$(req "$T_E2" "/users/$U1/estado" PATCH '{"estado":"inactivo"}'); check "e2 desactiva user e1" 404 "$c"
c=$(req "$T_E2" "/users/$U1" DELETE);                              check "e2 elimina user e1"   404 "$c"
c=$(req "$T_E2" "/users/$ME2/rol" PATCH "{\"rol_id\":\"$ROL_SUPER\"}"); check "e2 se auto-asigna super_admin" 422 "$c"   # bloqueado como regla de negocio
# Ascender a OTRO usuario de la propia empresa a un rol global: es la vía que
# esquiva la regla de "no puedes cambiar tu propio rol".
get "$T_E2" /users >/dev/null
OTRO_E2=$(python3 - "$ME2" <<'PYX'
import json, sys
d = json.load(open("/tmp/vbody")).get("data")
if isinstance(d, dict): d = d.get("items", [])
print(next((u["id"] for u in d if u["id"] != sys.argv[1]), ""))
PYX
)
c=$(req "$T_E2" "/users/$OTRO_E2/rol" PATCH "{\"rol_id\":\"$ROL_SUPER\"}")
check "e2 asciende a un colega suyo a super_admin" 403 "$c"

BODY_EVIL='{"email":"evil%s@x.pe","password":"Demo2026!","nombres":"E","apellido_paterno":"V","tipo_documento":"DNI","numero_documento":"9988776%s","rol_id":"ROLSUPER"}'
c=$(req "$T_E2"   /users POST "$(printf "$BODY_EVIL" 1 1 | sed "s/ROLSUPER/$ROL_SUPER/")"); check "admin e2 crea super_admin" 403 "$c"
c=$(req "$T_VET2" /users POST "$(printf "$BODY_EVIL" 2 2 | sed "s/ROLSUPER/$ROL_SUPER/")"); check "veterinario e2 crea super_admin" 403 "$c"

# Sufijo distinto en cada corrida: la prueba crea registros reales y no debe
# chocar con los de la corrida anterior. El DNI tiene ocho dígitos, así que el
# sufijo solo da 90 combinaciones: a la décima corrida el choque es probable y
# el fallo no dice nada sobre el sistema. Se buscan sufijos libres.
N=""
for _ in $(seq 1 25); do
  CAND=$(( (RANDOM % 90) + 10 ))
  c=$(req "$T_E2" /clientes POST '{"tipo_documento":"DNI","numero_documento":" 55-667.7'"$CAND"' ","nombres":"  josé   maría ","apellido_paterno":"DE LA cruz","apellido_materno":"soto","telefono":"(01) 445-5667","correo":"  Jose.Maria@GMAIL.COM  "}')
  [[ "$c" != 409 ]] && { N=$CAND; break; }
done
echo "═══ 5. Normalización (DNI 556677${N:-??}) ═══"
check "crea cliente con datos sucios" 201 "$c"
NUEVO=$(jid)
if [[ -n "$NUEVO" ]]; then
  get "$T_E2" "/clientes/$NUEVO" >/dev/null
  DOC="556677$N" python3 <<'PYX'
import json, os
d = json.load(open("/tmp/vbody"))["data"]
esperado = {"numero_documento": os.environ["DOC"], "nombres": "José María",
            "apellido_paterno": "De la Cruz", "apellido_materno": "Soto",
            "telefono": "014455667", "correo": "jose.maria@gmail.com"}
for k, v in esperado.items():
    print(("  ✓ " if d.get(k) == v else "  ✗ ") + f"{k}: {d.get(k)!r}" + ("" if d.get(k) == v else f"  (esperado {v!r})"))
PYX
fi
c=$(req "$T_E2" /clientes POST '{"tipo_documento":"DNI","numero_documento":"55.667.7'"$N"'","nombres":"Otro","apellido_paterno":"Clon"}')
check "documento duplicado tras normalizar" 409 "$c"

echo "═══ 6. Razas propias por empresa ═══"
get "$T_E2" /catalogos/especies >/dev/null; ESP=$(jid)
RAZA="raza SOLO de e2 $N-$(date +%H%M%S)"
c=$(req "$T_E2" /catalogos/razas POST "{\"especie_id\":\"$ESP\",\"nombre\":\"  $RAZA \"}")
check "e2 crea su propia raza" 201 "$c"
get "$T_E1" /catalogos/especies >/dev/null
VE=$(RAZA="$RAZA" python3 <<'PYX'
import json, os
d = json.load(open("/tmp/vbody"))["data"]
objetivo = os.environ["RAZA"].lower()
print("SI" if any(r["nombre"].lower() == objetivo for e in d for r in e.get("razas", [])) else "NO")
PYX
)
check "e1 NO ve la raza de e2" NO "$VE"

echo "═══ 7. Matriz de roles: cada quien ve lo suyo ═══"
# El aislamiento entre empresas ya estaba probado; esto prueba el de adentro.
# Durante mucho tiempo el menú ocultaba las pantallas y la API las servía igual:
# recepción podía leer los márgenes y el almacenero, la historia clínica.
T_RECEP=$(login recepcion@vetpatitas.pe)
T_ALM=$(login almacen@vetpatitas.pe)
T_VET1=$(login jperez@vetpatitas.pe)
T_GER=$(login gerencia@vetpatitas.pe)

# rol_token  descripción  método  ruta  esperado  [cuerpo]
matriz() {
  local tok="$1" desc="$2" met="$3" ruta="$4" esp="$5" cuerpo="${6:-}"
  local c
  if [[ "$met" == GET ]]; then c=$(get "$tok" "$ruta"); else c=$(req "$tok" "$ruta" "$met" "${cuerpo:-{\}}"); fi
  check "$desc" "$esp" "$c"
}

# --- Recepción: mostrador. Ni márgenes, ni legajos, ni compras, ni bitácora ---
matriz "$T_RECEP" "recepción NO ve el reporte ejecutivo"   GET /reportes/ejecutivo 403
matriz "$T_RECEP" "recepción NO ve reportes de ventas"     GET /reportes/ventas    403
matriz "$T_RECEP" "recepción NO ve el equipo"              GET /rrhh/equipo        403
matriz "$T_RECEP" "recepción NO ve las compras"            GET /compras/ordenes    403
matriz "$T_RECEP" "recepción NO ve la bitácora"            GET /auditoria          403
matriz "$T_RECEP" "recepción NO lista usuarios"            GET /users              403
matriz "$T_RECEP" "recepción SÍ ve la agenda"              GET /citas              200
matriz "$T_RECEP" "recepción SÍ ve la facturación"         GET /facturacion        200

# --- Veterinario: clínica y agenda; nada de dinero ---------------------------
matriz "$T_VET1" "veterinario NO ve los pagos"             GET /pagos              403
matriz "$T_VET1" "veterinario NO ve la caja"               GET /caja               403
matriz "$T_VET1" "veterinario NO ve el reporte ejecutivo"  GET /reportes/ejecutivo 403
matriz "$T_VET1" "veterinario SÍ ve las consultas"         GET /clinico/consultas  200

# --- Almacén: inventario y compras; la historia clínica no es suya -----------
matriz "$T_ALM" "almacén NO ve la historia clínica"        GET /clinico/consultas  403
matriz "$T_ALM" "almacén NO lista pacientes"               GET /mascotas           403
matriz "$T_ALM" "almacén SÍ ve el inventario"              GET /inventario/productos 200
matriz "$T_ALM" "almacén SÍ ve las compras"                GET /compras/ordenes    200

# --- Gerencia: lo ve todo, no toca nada --------------------------------------
matriz "$T_GER" "gerencia SÍ ve el reporte ejecutivo"      GET /reportes/ejecutivo 200
matriz "$T_GER" "gerencia NO crea clientes"                POST /clientes          403 \
  '{"tipo_documento":"DNI","numero_documento":"70707070","nombres":"X","apellido_paterno":"Y"}'

# --- Configuración de la empresa y estado ante SUNAT -------------------------
get "$T_E1" /empresas >/dev/null; EMP1=$(jid)
matriz "$T_RECEP" "recepción NO cambia el IGV ni las series" PATCH "/empresas/$EMP1" 403 \
  '{"igv_tasa":0.05,"serie_factura_default":"F999"}'
matriz "$T_VET1"  "veterinario NO cambia los datos de la empresa" PATCH "/empresas/$EMP1" 403 \
  '{"nombre_comercial":"Otro nombre"}'
get "$T_E1" /facturacion >/dev/null; CMP1=$(jid)
matriz "$T_RECEP" "recepción NO marca un comprobante como aceptado por SUNAT" \
  PATCH "/facturacion/$CMP1/sunat" 403 '{"estado":"aceptado_sunat","sunat_codigo":"0"}'

# --- Escribir en la historia clínica exige ser clínico -----------------------
get "$T_E1" /mascotas >/dev/null; MASC1=$(jid)
matriz "$T_ALM" "almacén NO escribe notas médicas" POST /clinico/notas 403 \
  "{\"mascota_id\":\"$MASC1\",\"nota\":\"no deberia entrar\"}"

# --- RRHH: fichar y pedir permisos es autoservicio ---------------------------
OTRO=$(python3 -c "import json;print(json.load(open('/tmp/vbody')).get('x',''))" 2>/dev/null)
get "$T_E1" /rrhh/equipo >/dev/null
OTRO_USER=$(python3 <<'PYX'
import json
d = json.load(open("/tmp/vbody")).get("data") or []
print(next((x["user_id"] for x in d if x.get("user_id")), ""))
PYX
)
if [[ -n "$OTRO_USER" ]]; then
  matriz "$T_VET1" "veterinario NO ficha por un compañero" POST /rrhh/asistencia/marcar 403 \
    "{\"userId\":\"$OTRO_USER\"}"
  matriz "$T_VET1" "veterinario NO pide vacaciones a nombre de otro" POST /rrhh/permisos 403 \
    "{\"user_id\":\"$OTRO_USER\",\"tipo\":\"vacaciones\",\"fecha_inicio\":\"2027-01-05\",\"fecha_fin\":\"2027-01-06\"}"
fi

echo "═══ 8. Archivos clínicos: el almacén no sabe de empresas ═══"
# MinIO no filtra por empresa: la clave del objeto es tan sensible como la fila
# que la guarda, y el ticket de descarga la firmaba sin mirar de quién era.
printf 'RADIOGRAFIA DE PRUEBA' > /tmp/vet-rx.png
SUBIDA=$(curl -s -X POST "$API/archivos" -H "Authorization: Bearer $T_VET1" \
         -F "file=@/tmp/vet-rx.png;type=image/png")
KEY=$(python3 -c 'import sys,json;print(json.load(sys.stdin).get("data",{}).get("storage_key",""))' <<<"$SUBIDA")
if [[ -n "$KEY" ]]; then ok=$((ok+1)); else fail=$((fail+1)); FALLOS+=("el veterinario no pudo subir un archivo :: $SUBIDA"); fi

c=$(curl -s -o /tmp/vbody -w '%{http_code}' -G "$API/archivos/ticket-descarga" \
    --data-urlencode "key=$KEY" -H "Authorization: Bearer $T_VET2")
check "la otra empresa NO descarga el archivo" 404 "$c"

c=$(curl -s -o /tmp/vbody -w '%{http_code}' -G "$API/archivos/ticket-descarga" \
    --data-urlencode "key=$KEY" -H "Authorization: Bearer $T_VET1")
check "el veterinario que lo subió SÍ lo descarga" 200 "$c"

c=$(curl -s -o /tmp/vbody -w '%{http_code}' -G "$API/archivos/ticket-descarga" \
    --data-urlencode "key=e_00000000-0000-0000-0000-000000000000/../clinico/x" \
    -H "Authorization: Bearer $T_VET1")
check "ruta relativa rechazada" 422 "$c"

c=$(curl -s -o /tmp/vbody -w '%{http_code}' -G "$API/archivos/ticket-subida" \
    --data-urlencode "nombre=x.pdf" --data-urlencode "area=nomina" \
    -H "Authorization: Bearer $T_VET1")
check "área de archivo inventada rechazada" 422 "$c"

printf '<script>alert(1)</script>' > /tmp/vet-x.html
c=$(curl -s -o /tmp/vbody -w '%{http_code}' -X POST "$API/archivos" \
    -H "Authorization: Bearer $T_VET1" -F "file=@/tmp/vet-x.html;type=text/html")
check "subida de HTML rechazada" 400 "$c"

echo
echo "═══════════════════════════════════════"
echo "  OK: $ok    FALLOS: $fail"
for f in "${FALLOS[@]}"; do echo "  ✗ $f"; done
