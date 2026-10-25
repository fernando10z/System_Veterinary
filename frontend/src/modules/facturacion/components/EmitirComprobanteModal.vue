<template>
  <div class="modal-back" v-dialogo="() => $emit('close')">
    <div class="modal modal-xwide" @click.stop>
      <div class="m-head"><h3>Emitir comprobante</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <!-- Cliente -->
        <div class="field">
          <label for="emitircomp-q">Cliente <span class="req">*</span></label>
          <div v-if="clienteSel" class="sel-cliente">
            <div class="avatar-sm">{{ iniciales(clienteSel.nombre_completo) }}</div>
            <div class="grow">
              <strong>{{ clienteSel.nombre_completo }}</strong>
              <small class="codigo">{{ clienteSel.numero_documento }}</small>
            </div>
            <button v-if="!bloquearCliente" class="btn mini" @click="limpiarCliente">Cambiar</button>
          </div>
          <template v-else>
            <div class="fil grow" data-no-dirty>
              <Search :size="14" />
              <input id="emitircomp-q"
                v-model="q" type="search" aria-label="Buscar cliente"
                placeholder="Buscar cliente por nombre, documento o mascota…" @input="buscarDebounced"
              />
              <Loader2 v-if="buscando" :size="14" class="spin" />
            </div>
            <small v-if="q.length >= 2 && !buscando && buscado && !resultados.length" class="muted">
              Sin coincidencias para “{{ q }}”.
            </small>
            <div v-if="resultados.length" class="resultados">
              <button v-for="c in resultados" :key="c.id" class="res-item" @click="elegir(c)">
                <strong>{{ c.nombre_completo }}</strong>
                <span class="codigo muted">{{ c.numero_documento }}</span>
              </button>
            </div>
          </template>
        </div>

        <div v-if="clienteSel" class="form-grid" style="margin-top: 14px">
          <div class="field">
            <label for="emit-tipo">Tipo de comprobante</label>
            <select id="emit-tipo" v-model="form.tipo">
              <option value="boleta">Boleta</option>
              <option value="factura" :disabled="!esRuc">Factura {{ esRuc ? "" : "(requiere RUC)" }}</option>
              <option value="nota_venta">Nota de venta</option>
            </select>
          </div>
          <div class="field">
            <label for="emit-fecha">Fecha de emisión</label>
            <input id="emit-fecha" v-model="form.fecha_emision" type="date" :max="hoy" />
          </div>
        </div>

        <!-- Pendiente de facturar del cliente -->
        <template v-if="clienteSel">
          <div class="section-title" style="margin-top: 16px">Pendiente de facturar</div>

          <div v-if="cargandoPend" class="loading-mini" style="padding: 12px 0">
            <Loader2 :size="14" class="spin" /> Buscando atenciones sin cobrar…
          </div>

          <div v-else-if="!lineas.length" class="callout" style="margin-top: 8px">
            <Info :size="15" />
            <span>Este cliente no tiene servicios ni productos pendientes de cobro.</span>
          </div>

          <div v-else class="tabla-wrap" style="margin-top: 8px">
            <table>
              <thead>
                <tr>
                  <th style="width: 34px"></th>
                  <th>Concepto</th><th>Tipo</th>
                  <th class="num">Cant.</th><th class="num">P. unit.</th><th class="num">Total</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(l, i) in lineas" :key="i" :class="{ otra: mascota && l.mascota && l.mascota !== mascota }">
                  <td><input v-model="l.incluir" type="checkbox" :aria-label="`Incluir ${l.descripcion}`" /></td>
                  <td>
                    <strong>{{ l.descripcion }}</strong>
                    <br /><small class="muted codigo">{{ l.codigo }}</small>
                    <small v-if="l.mascota && lineasDeVariasMascotas" class="muted"> · {{ l.mascota }}</small>
                  </td>
                  <td><span class="tag">{{ l.tipo === "servicio" ? "Servicio" : "Producto" }}</span></td>
                  <td class="num cifra">{{ l.cantidad }}</td>
                  <td class="num cifra">{{ fmtSoles(l.precio_unitario) }}</td>
                  <td class="num cifra">{{ fmtSoles(l.total) }}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div v-if="lineas.length" class="totales">
            <div><span>Seleccionado</span><span class="cifra">{{ seleccionadas.length }} de {{ lineas.length }}</span></div>
            <div class="total"><span>Total a cobrar</span><span class="cifra">{{ fmtSoles(totalSeleccionado) }}</span></div>
          </div>
        </template>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" :disabled="guardando" @click="$emit('close')">Cancelar</button>
        <button
          v-if="!soloCobrar"
          :class="['btn', puedeCobrar ? '' : 'primary']"
          :disabled="guardando || !seleccionadas.length"
          @click="emitir(false)"
        >
          {{ guardando && !cobrarTras ? "Emitiendo…" : "Emitir comprobante" }}
        </button>
        <button
          v-if="puedeCobrar"
          class="btn primary"
          :disabled="guardando || !seleccionadas.length"
          @click="emitir(true)"
        >
          <Wallet :size="14" /> {{ guardando && cobrarTras ? "Emitiendo…" : `Emitir y cobrar ${fmtSoles(totalSeleccionado)}` }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, computed, onMounted } from "vue";
import { AlertCircle, Search, Loader2, Info, Wallet } from "lucide-vue-next";
import { facturacionApi } from "../api/facturacion.api.js";
import { clientesApi } from "../../clientes/api/clientes.api.js";
import { clinicoApi } from "../../clinico/api/clinico.api.js";
import { fmtSoles, iniciales } from "../../../shared/components/ui/format.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { notify } from "../../../shared/composables/useNotify.js";
import { hoyISO } from "@/shared/utils/fechas.js";
import { uuid } from "@/shared/utils/uuid.js";

/**
 * Emisión desde lo pendiente de facturar del cliente. Se puede abrir ya con el
 * cliente elegido (desde la consulta, la cita o la sala de espera): así la
 * recepción pasa de "atendido" a "boleta + cobro" en dos clics.
 */
const props = defineProps({
  /** { id, nombre_completo?, numero_documento? }: cliente ya elegido. */
  cliente: { type: Object, default: null },
  /** Nombre de la mascota atendida: resalta sus líneas y se envía como contexto. */
  mascota: { type: String, default: "" },
  mascotaId: { type: String, default: "" },
  consultaId: { type: String, default: "" },
  citaId: { type: String, default: "" },
  /** Solo muestra "Emitir y cobrar" (flujo rápido desde la atención). */
  soloCobrar: { type: Boolean, default: false },
});
const emit = defineEmits(["close", "emitido"]);

const { hasPermission } = useAuth();
const puedeCobrar = computed(() => hasPermission("pagos:registrar"));
const bloquearCliente = computed(() => !!props.cliente?.id);

const q = ref("");
const resultados = ref([]);
const buscando = ref(false);
const buscado = ref(false);
const clienteSel = ref(null);
const lineas = ref([]);
const cargandoPend = ref(false);
const guardando = ref(false);
const cobrarTras = ref(false);
const error = ref("");
const hoy = hoyISO();

const form = reactive({ tipo: "boleta", fecha_emision: hoy });

// Una sola clave por apertura del modal: un doble clic o un reintento tras un
// corte no emite dos comprobantes.
const idempotencyKey = uuid();

// La factura exige RUC: se decide por el tipo de documento, no por el largo.
const esRuc = computed(() => {
  const c = clienteSel.value;
  if (!c) return false;
  if (c.tipo_documento) return c.tipo_documento === "RUC";
  return /^(10|15|17|20)\d{9}$/.test(c.numero_documento || "");
});
const seleccionadas = computed(() => lineas.value.filter((l) => l.incluir));
const totalSeleccionado = computed(() => seleccionadas.value.reduce((s, l) => s + Number(l.total), 0));
const lineasDeVariasMascotas = computed(() => new Set(lineas.value.map((l) => l.mascota).filter(Boolean)).size > 1);

let timer = null;
function buscarDebounced() {
  clearTimeout(timer);
  buscado.value = false;
  if (q.value.length < 2) { resultados.value = []; return; }
  timer = setTimeout(async () => {
    buscando.value = true;
    try {
      const r = await clientesApi.buscar(q.value, 8);
      resultados.value = r.data ?? [];
    } catch (e) {
      resultados.value = [];
      notify.toast(`No se pudo buscar: ${e.message}`, "error");
    } finally {
      buscando.value = false;
      buscado.value = true;
    }
  }, 300);
}

function limpiarCliente() {
  clienteSel.value = null;
  lineas.value = [];
}

async function elegir(c) {
  clienteSel.value = { ...c };
  resultados.value = [];
  q.value = "";
  cargandoPend.value = true;
  try {
    // La búsqueda no trae el tipo de documento: se lee la ficha para decidir
    // si puede recibir factura.
    const [ficha, pend] = await Promise.all([
      clientesApi.obtener(c.id).catch(() => null),
      clinicoApi.pendienteFacturar(c.id),
    ]);
    if (ficha?.data) {
      const d = ficha.data;
      clienteSel.value = {
        ...clienteSel.value,
        tipo_documento: d.tipo_documento,
        numero_documento: d.numero_documento ?? clienteSel.value.numero_documento,
        nombre_completo: clienteSel.value.nombre_completo
          || d.nombre_completo
          || [d.nombres, d.apellido_paterno, d.apellido_materno].filter(Boolean).join(" "),
      };
    }
    // Una factura exige RUC; si el cliente no lo tiene, boleta por defecto.
    form.tipo = esRuc.value ? "factura" : "boleta";
    const d = pend.data ?? {};
    lineas.value = [...(d.servicios ?? []), ...(d.insumos ?? [])].map((l) => ({ ...l, incluir: true }));
  } catch (e) {
    error.value = `No se pudo cargar lo pendiente de facturar: ${e.message}`;
  } finally {
    cargandoPend.value = false;
  }
}

async function emitir(cobrar = false) {
  if (guardando.value) return;
  error.value = "";
  if (form.tipo === "factura" && !esRuc.value) {
    error.value = "La factura requiere un cliente con RUC. Emite una boleta.";
    return;
  }
  cobrarTras.value = cobrar;
  guardando.value = true;
  try {
    // Se mandan las líneas explícitas: así el usuario decide qué cobra ahora.
    const items = seleccionadas.value.map((l) => ({
      tipo_item: l.tipo,
      descripcion: l.descripcion,
      codigo: l.codigo || undefined,
      cantidad: Number(l.cantidad),
      precio_unitario: Number(l.precio_unitario),
      descuento: Number(l.descuento ?? 0),
      afecto_igv: l.afecto_igv ?? true,
      servicio_id: l.servicio_id || undefined,
      producto_id: l.producto_id || undefined,
      orden_servicio_id: l.orden_servicio_id || undefined,
      insumo_id: l.insumo_id || undefined,
    }));

    const r = await facturacionApi.emitir({
      cliente_id: clienteSel.value.id,
      tipo: form.tipo,
      fecha_emision: form.fecha_emision,
      items,
      ...(props.mascotaId ? { mascota_id: props.mascotaId } : {}),
      ...(props.consultaId ? { consulta_id: props.consultaId } : {}),
      ...(props.citaId ? { cita_id: props.citaId } : {}),
      idempotency_key: idempotencyKey,
    });
    emit("emitido", {
      ...r.data,
      cliente_id: clienteSel.value.id,
      cliente: clienteSel.value.nombre_completo,
      saldo_pendiente: r.data?.saldo_pendiente ?? r.data?.total,
    }, { cobrar });
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

onMounted(() => {
  if (props.cliente?.id) elegir(props.cliente);
});
</script>

<style scoped>
.sel-cliente {
  display: flex; align-items: center; gap: 11px;
  padding: 10px 12px; border-radius: 10px;
  background: var(--emerald-soft); border: 1px solid var(--emerald-line);
}
.sel-cliente strong { display: block; font-size: 13.5px; color: var(--ink); }
.sel-cliente small { font-size: 11.5px; color: var(--ink-3); }
.resultados { margin-top: 8px; max-height: 200px; overflow-y: auto; border: 1px solid var(--line); border-radius: 10px; }
.res-item {
  display: flex; justify-content: space-between; gap: 10px; width: 100%;
  padding: 9px 11px; border: none; background: none; cursor: pointer;
  text-align: left; font-size: 12.5px; border-bottom: 1px solid var(--line-soft);
}
.res-item:last-child { border-bottom: none; }
.res-item:hover { background: var(--bg-soft); }
.totales { margin-top: 14px; margin-left: auto; width: 280px; display: flex; flex-direction: column; gap: 6px; }
.totales > div { display: flex; justify-content: space-between; font-size: 13px; color: var(--ink-2); }
.totales .total { border-top: 1px solid var(--line); padding-top: 8px; font-size: 16px; font-weight: 700; color: var(--ink); }
.req { color: var(--red); }
.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
tr.otra { opacity: 0.75; }
</style>
