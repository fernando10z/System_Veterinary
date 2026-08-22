<template>
  <div>
    <PageHeader
      eyebrow="Administración"
      title="Facturación"
      :subtitle="meta.total ? `${meta.total} comprobantes en el periodo` : 'Boletas, facturas y notas de venta'"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
        <button v-if="puedeEmitir" class="btn primary" @click="modalEmitir = true">
          <Plus :size="14" /> Emitir comprobante
        </button>
      </template>
    </PageHeader>

    <div class="stat-row">
      <div class="stat">
        <div class="stat-label">Facturado <span class="icon-tile"><Receipt :size="14" /></span></div>
        <div class="stat-val">{{ fmtSoles(totales.facturado) }}</div>
        <div class="stat-meta"><span class="trend">{{ meta.total ?? 0 }}</span> comprobantes</div>
      </div>
      <div class="stat">
        <div class="stat-label">Cobrado <span class="icon-tile"><Wallet :size="14" /></span></div>
        <div class="stat-val">{{ fmtSoles(totales.cobrado) }}</div>
        <div class="stat-meta">{{ pctCobrado }}% del total</div>
      </div>
      <div class="stat">
        <div class="stat-label">Pendiente <span class="icon-tile amber"><CreditCard :size="14" /></span></div>
        <div class="stat-val">{{ fmtSoles(totales.pendiente) }}</div>
        <div class="stat-meta">por cobrar</div>
      </div>
      <div class="stat">
        <div class="stat-label">Ticket promedio <span class="icon-tile violet"><TrendingUp :size="14" /></span></div>
        <div class="stat-val">{{ fmtSoles(ticket) }}</div>
        <div class="stat-meta">por comprobante</div>
      </div>
    </div>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Receipt :size="14" /></span>
          Comprobantes
          <span class="head-meta">{{ meta.total ?? comprobantes.length }}</span>
        </h2>
      </header>

      <div class="module-panel-toolbar">
        <div class="fil grow">
          <Search :size="14" />
          <input v-model="filtros.buscar" type="search" placeholder="Número, cliente o documento…" @input="debounced" />
        </div>
        <div class="fil">
          <CalendarRange :size="14" />
          <input v-model="filtros.desde" type="date" @change="recargar" />
        </div>
        <div class="fil">
          <span class="muted">a</span>
          <input v-model="filtros.hasta" type="date" @change="recargar" />
        </div>
        <div class="fil">
          <Filter :size="14" />
          <select v-model="filtros.tipo" @change="recargar">
            <option value="">Todos los tipos</option>
            <option value="boleta">Boleta</option>
            <option value="factura">Factura</option>
            <option value="nota_venta">Nota de venta</option>
          </select>
        </div>
        <div class="fil">
          <select v-model="filtros.estadoPago" @change="recargar">
            <option value="">Todo estado de pago</option>
            <option value="pendiente">Pendiente</option>
            <option value="parcial">Parcial</option>
            <option value="pagado">Pagado</option>
          </select>
        </div>
        <div class="toolbar-spacer"></div>
        <span v-if="cargando" class="loading-mini"><Loader2 :size="13" class="spin" /> Cargando…</span>
      </div>

      <div v-if="!cargando && !comprobantes.length" class="module-panel-body module-empty">
        <div class="empty-icon"><Receipt :size="22" /></div>
        <h3>Sin comprobantes en el periodo</h3>
        <p>Emite un comprobante desde la atención o directamente aquí.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Comprobante</th><th>Cliente</th><th>Emisión</th>
              <th class="num">Total</th><th class="num">Saldo</th>
              <th>Pago</th><th>Estado</th><th class="acciones-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="c in comprobantes" :key="c.id" class="clickable" @click="verDetalle(c)">
              <td>
                <div class="stack">
                  <strong class="mono">{{ c.numero_completo }}</strong>
                  <small class="muted">{{ capitalizar(c.tipo) }}</small>
                </div>
              </td>
              <td>
                <div class="stack">
                  <span>{{ c.cliente_facturacion || c.cliente }}</span>
                  <small class="muted mono">{{ c.cliente_tipo_doc }} {{ c.cliente_documento }}</small>
                </div>
              </td>
              <td class="mono">{{ fmtFechaHora(c.fecha_emision) }}</td>
              <td class="num mono">{{ fmtSoles(c.total) }}</td>
              <td class="num mono">
                <span :class="Number(c.saldo_pendiente) > 0 ? 'deuda' : 'muted'">
                  {{ fmtSoles(c.saldo_pendiente) }}
                </span>
              </td>
              <td>
                <span :class="['estado-pill', tonePago(c.estado_pago)]">
                  <span class="dot"></span>{{ capitalizar(c.estado_pago) }}
                </span>
              </td>
              <td>
                <span :class="['estado-pill', toneEstado(c.estado)]">
                  <span class="dot"></span>{{ capitalizar(c.estado) }}
                </span>
              </td>
              <td class="acciones-col" @click.stop>
                <div class="row-actions">
                  <button class="btn mini" title="Ver detalle" @click="verDetalle(c)"><FileText :size="13" /></button>
                  <button
                    v-if="puedeAnular && !c.anulado_at && c.estado !== 'anulado'"
                    class="btn mini"
                    title="Anular"
                    @click="anular(c)"
                  >
                    <Ban :size="13" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="meta.pages > 1" class="module-panel-foot">
        <span class="muted">Página {{ meta.page }} de {{ meta.pages }}</span>
        <div class="wrap-actions">
          <button class="btn" :disabled="meta.page <= 1" @click="irPagina(meta.page - 1)">Anterior</button>
          <button class="btn" :disabled="meta.page >= meta.pages" @click="irPagina(meta.page + 1)">Siguiente</button>
        </div>
      </div>
    </section>

    <EmitirComprobanteModal
      v-if="modalEmitir"
      @close="modalEmitir = false"
      @emitido="onEmitido"
    />

    <ComprobanteDetalleModal
      v-if="detalleId"
      :comprobante-id="detalleId"
      @close="detalleId = null"
      @cambiado="cargar"
    />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  Receipt, Wallet, CreditCard, TrendingUp, Search, Plus, RefreshCw, Loader2,
  Filter, CalendarRange, FileText, Ban,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import EmitirComprobanteModal from "../components/EmitirComprobanteModal.vue";
import ComprobanteDetalleModal from "../components/ComprobanteDetalleModal.vue";
import { facturacionApi } from "../api/facturacion.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtSoles } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const { hasPermission } = useAuth();
const puedeEmitir = computed(() => hasPermission("facturacion:emitir"));
const puedeAnular = computed(() => hasPermission("facturacion:anular"));

const comprobantes = ref([]);
const meta = ref({});
const cargando = ref(false);
const modalEmitir = ref(false);
const detalleId = ref(null);

const hoy = new Date();
const inicioMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
const filtros = reactive({
  buscar: "",
  desde: inicioMes.toISOString().slice(0, 10),
  hasta: hoy.toISOString().slice(0, 10),
  tipo: "",
  estadoPago: "",
  page: 1,
});

const totales = computed(() => meta.value.totales ?? { facturado: 0, cobrado: 0, pendiente: 0 });
const pctCobrado = computed(() => {
  const f = Number(totales.value.facturado);
  return f ? Math.round((Number(totales.value.cobrado) / f) * 100) : 0;
});
const ticket = computed(() => {
  const n = meta.value.total ?? 0;
  return n ? Number(totales.value.facturado) / n : 0;
});

function tonePago(e) {
  return { pagado: "ok", parcial: "warn", pendiente: "danger", anulado: "neutral" }[e] || "neutral";
}
function toneEstado(e) {
  return {
    emitido: "info", aceptado_sunat: "ok", enviado_sunat: "warn",
    rechazado_sunat: "danger", anulado: "neutral", borrador: "neutral",
  }[e] || "neutral";
}

let timer = null;
function debounced() { clearTimeout(timer); timer = setTimeout(recargar, 350); }
function recargar() { filtros.page = 1; cargar(); }
function irPagina(p) { filtros.page = p; cargar(); }
function verDetalle(c) { detalleId.value = c.id; }

function onEmitido(data) {
  modalEmitir.value = false;
  cargar();
  notify.success("Comprobante emitido", `${data.numero_completo} · ${fmtSoles(data.total)}`);
}

async function anular(c) {
  const motivo = await notify.prompt(`Anular ${c.numero_completo}`, {
    text: "Los servicios e insumos volverán a quedar pendientes de facturar.",
    placeholder: "Motivo de la anulación",
  });
  if (!motivo) return;
  try {
    await facturacionApi.anular(c.id, motivo);
    notify.success("Comprobante anulado");
    cargar();
  } catch (e) {
    notify.error("No se pudo anular", e.message);
  }
}

async function cargar() {
  cargando.value = true;
  try {
    const hastaExcl = new Date(filtros.hasta);
    hastaExcl.setDate(hastaExcl.getDate() + 1);
    const r = await facturacionApi.listar({
      buscar: filtros.buscar || undefined,
      desde: filtros.desde,
      hasta: hastaExcl.toISOString().slice(0, 10),
      tipo: filtros.tipo || undefined,
      estadoPago: filtros.estadoPago || undefined,
      page: filtros.page,
      pageSize: 25,
    });
    comprobantes.value = r.data ?? [];
    meta.value = r.meta ?? {};
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.deuda { color: var(--red-ink); font-weight: 600; }
.btn.mini { height: 26px; padding: 0 8px; font-size: 11.5px; }
</style>
