#!/usr/bin/env bash
# =============================================================================
# Verificación funcional y de aislamiento del ERP veterinario.
#
# Cubre: login de las dos empresas, las 46 rutas GET con ambas, intentos de
# lectura y escritura cruzada entre empresas, escalada de privilegios,
# normalización del dato y razas propias por empresa.
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
 /citas /citas/agenda-dia /clientes /clientes/comunicaciones
 /clinico/cirugias /clinico/consultas /clinico/hospitalizaciones
 /compras/ordenes /compras/pagos /compras/proveedores
 /dashboard /dashboard/recordatorios /empresas/actual
 /facturacion /facturacion/cuentas-por-cobrar
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
# chocar con los de la corrida anterior.
N=$(( (RANDOM % 90) + 10 ))
echo "═══ 5. Normalización (DNI 556677$N) ═══"
c=$(req "$T_E2" /clientes POST '{"tipo_documento":"DNI","numero_documento":" 55-667.7'"$N"' ","nombres":"  josé   maría ","apellido_paterno":"DE LA cruz","apellido_materno":"soto","telefono":"(01) 445-5667","correo":"  Jose.Maria@GMAIL.COM  "}')
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
c=$(req "$T_E2" /catalogos/razas POST "{\"especie_id\":\"$ESP\",\"nombre\":\"  raza   SOLO de e2 $N \"}")
check "e2 crea su propia raza" 201 "$c"
get "$T_E1" /catalogos/especies >/dev/null
VE=$(python3 <<'PYX'
import json
d = json.load(open("/tmp/vbody"))["data"]
print("SI" if any(r["nombre"].lower().startswith("raza solo de e2") for e in d for r in e.get("razas", [])) else "NO")
PYX
)
check "e1 NO ve la raza de e2" NO "$VE"

echo
echo "═══════════════════════════════════════"
echo "  OK: $ok    FALLOS: $fail"
for f in "${FALLOS[@]}"; do echo "  ✗ $f"; done
