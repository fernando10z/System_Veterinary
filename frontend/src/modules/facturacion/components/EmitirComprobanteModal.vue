<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal modal-xwide" @click.stop>
      <div class="m-head"><h3>Emitir comprobante</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <!-- Cliente -->
        <div class="field">
          <label>Cliente <span class="req">*</span></label>
          <div v-if="clienteSel" class="sel-cliente">
            <div class="avatar-sm">{{ iniciales(clienteSel.nombre_completo) }}</div>
            <div class="grow">
              <strong>{{ clienteSel.nombre_completo }}</strong>
              <small class="mono">{{ clienteSel.numero_documento }}</small>
            </div>
            <button class="btn mini" @click="limpiarCliente">Cambiar</button>
          </div>
          <template v-else>
            <div class="fil grow">
              <Search :size="14" />
              <input v-model="q" type="search" placeholder="Buscar cliente por nombre, documento o mascota…" @input="buscarDebounced" />
            </div>
            <div v-if="resultados.length" class="resultados">
              <button v-for="c in resultados" :key="c.id" class="res-item" @click="elegir(c)">
                <strong>{{ c.nombre_completo }}</strong>
                <span class="mono muted">{{ c.numero_documento }}</span>
              </button>
            </div>
          </template>
        </div>

        <div v-if="clienteSel" class="form-grid">
          <div class="field">
            <label>Tipo de comprobante</label>
            <select v-model="form.tipo">
              <option value="boleta">Boleta</option>
              <option value="factura" :disabled="!esRuc">Factura {{ esRuc ? "" : "(requiere RUC)" }}</option>
              <option value="nota_venta">Nota de venta</option>
            </select>
          </div>
          <div class="field">
            <label>Fecha de emisión</label>
            <input v-model="form.fecha_emision" type="date" />
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
                <tr v-for="(l, i) in lineas" :key="i">
                  <td><input v-model="l.incluir" type="checkbox" /></td>
                  <td>
                    <strong>{{ l.descripcion }}</strong>
                    <br /><small class="muted mono">{{ l.codigo }}</small>
                  </td>
                  <td><span class="tag">{{ l.tipo === "servicio" ? "Servicio" : "Producto" }}</span></td>
                  <td class="num mono">{{ l.cantidad }}</td>
                  <td class="num mono">{{ fmtSoles(l.precio_unitario) }}</td>
                  <td class="num mono">{{ fmtSoles(l.total) }}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div v-if="lineas.length" class="totales">
            <div><span>Seleccionado</span><span class="mono">{{ seleccionadas.length }} de {{ lineas.length }}</span></div>
            <div class="total"><span>Total a cobrar</span><span class="mono">{{ fmtSoles(totalSeleccionado) }}</span></div>
          </div>
        </template>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button class="btn primary" :disabled="guardando || !seleccionadas.length" @click="emitir">
          {{ guardando ? "Emitiendo…" : "Emitir comprobante" }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, computed } from "vue";
import { AlertCircle, Search, Loader2, Info } from "lucide-vue-next";
import { facturacionApi } from "../api/facturacion.api.js";
import { clientesApi } from "../../clientes/api/clientes.api.js";
import { clinicoApi } from "../../clinico/api/clinico.api.js";
import { fmtSoles, iniciales } from "../../../shared/components/ui/format.js";

const emit = defineEmits(["close", "emitido"]);

const q = ref("");
const resultados = ref([]);
const clienteSel = ref(null);
const lineas = ref([]);
const cargandoPend = ref(false);
const guardando = ref(false);
const error = ref("");

const form = reactive({ tipo: "boleta", fecha_emision: new Date().toISOString().slice(0, 10) });

const esRuc = computed(() => clienteSel.value?.numero_documento?.length === 11);
const seleccionadas = computed(() => lineas.value.filter((l) => l.incluir));
const totalSeleccionado = computed(() => seleccionadas.value.reduce((s, l) => s + Number(l.total), 0));

let timer = null;
function buscarDebounced() {
  clearTimeout(timer);
  if (q.value.length < 2) { resultados.value = []; return; }
  timer = setTimeout(async () => {
    const r = await clientesApi.buscar(q.value, 8);
    resultados.value = r.data ?? [];
  }, 300);
}

function limpiarCliente() {
  clienteSel.value = null;
  lineas.value = [];
}

async function elegir(c) {
  clienteSel.value = c;
  resultados.value = [];
  q.value = "";
  // Una factura exige RUC; si el cliente no lo tiene, boleta por defecto.
  if (c.numero_documento?.length !== 11) form.tipo = "boleta";

  cargandoPend.value = true;
  try {
    const r = await clinicoApi.pendienteFacturar(c.id);
    const d = r.data ?? {};
    lineas.value = [...(d.servicios ?? []), ...(d.insumos ?? [])].map((l) => ({ ...l, incluir: true }));
  } finally {
    cargandoPend.value = false;
  }
}

async function emitir() {
  error.value = "";
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
    });
    emit("emitido", r.data);
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}
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
</style>
