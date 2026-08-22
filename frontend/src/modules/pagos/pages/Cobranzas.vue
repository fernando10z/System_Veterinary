<template>
  <div>
    <PageHeader
      eyebrow="Administración"
      title="Cobranzas"
      :subtitle="`${resumen.documentos ?? 0} documentos por cobrar · ${resumen.clientes ?? 0} clientes`"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
      </template>
    </PageHeader>

    <div class="stat-row">
      <div class="stat">
        <div class="stat-label">Deuda total <span class="icon-tile"><CreditCard :size="14" /></span></div>
        <div class="stat-val">{{ fmtSoles(resumen.total_deuda) }}</div>
        <div class="stat-meta">{{ resumen.documentos ?? 0 }} comprobantes</div>
      </div>
      <div class="stat">
        <div class="stat-label">Vencido <span class="icon-tile"><AlertTriangle :size="14" /></span></div>
        <div class="stat-val">{{ fmtSoles(resumen.vencido) }}</div>
        <div class="stat-meta"><span class="trend flat">{{ pctVencido }}%</span> de la deuda</div>
      </div>
      <div class="stat">
        <div class="stat-label">Por vencer <span class="icon-tile amber"><Clock :size="14" /></span></div>
        <div class="stat-val">{{ fmtSoles(resumen.por_vencer) }}</div>
        <div class="stat-meta">aún dentro de plazo</div>
      </div>
      <div class="stat">
        <div class="stat-label">Cobrado hoy <span class="icon-tile violet"><Wallet :size="14" /></span></div>
        <div class="stat-val">{{ fmtSoles(cobradoHoy) }}</div>
        <div class="stat-meta">{{ pagosHoy.length }} operaciones</div>
      </div>
    </div>

    <!-- Aging: cuánto está en cada tramo de mora -->
    <section class="module-panel">
      <header class="module-panel-head">
        <h2><span class="head-icon"><BarChart3 :size="14" /></span> Antigüedad de la deuda</h2>
      </header>
      <div class="module-panel-body aging">
        <div v-for="t in tramos" :key="t.key" class="aging-item">
          <div class="l">{{ t.label }}</div>
          <div class="n mono">{{ fmtSoles(t.monto) }}</div>
          <div class="barra">
            <div class="fill" :class="t.tone" :style="{ width: t.pct + '%' }"></div>
          </div>
          <div class="d">{{ t.docs }} doc.</div>
        </div>
      </div>
    </section>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><CreditCard :size="14" /></span>
          Cuentas por cobrar
          <span class="head-meta">{{ cuentas.length }}</span>
        </h2>
      </header>

      <div v-if="!cargando && !cuentas.length" class="module-panel-body module-empty">
        <div class="empty-icon"><CheckCircle2 :size="22" /></div>
        <h3>Sin deuda pendiente</h3>
        <p>Todos los comprobantes están cobrados.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Comprobante</th><th>Cliente</th><th>Contacto</th>
              <th>Emisión</th><th>Vencimiento</th>
              <th class="num">Total</th><th class="num">Saldo</th>
              <th>Mora</th><th class="acciones-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="c in cuentas" :key="c.id">
              <td class="mono"><strong>{{ c.numero_completo }}</strong></td>
              <td>{{ c.cliente }}</td>
              <td class="mono">{{ c.cliente_telefono || "—" }}</td>
              <td class="mono">{{ fmtDate(c.fecha_emision) }}</td>
              <td class="mono">{{ c.fecha_vencimiento ? fmtDate(c.fecha_vencimiento) : "—" }}</td>
              <td class="num mono">{{ fmtSoles(c.total) }}</td>
              <td class="num mono deuda">{{ fmtSoles(c.saldo_pendiente) }}</td>
              <td>
                <span :class="['estado-pill', toneTramo(c.tramo)]">
                  {{ labelTramo(c.tramo) }}
                </span>
              </td>
              <td class="acciones-col">
                <button v-if="puedeCobrar" class="btn mini primary" @click="cobrar(c)">Cobrar</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Wallet :size="14" /></span>
          Cobros recientes
          <span class="head-meta">{{ pagos.length }}</span>
        </h2>
      </header>

      <div v-if="!pagos.length" class="module-panel-body module-empty">
        <div class="empty-icon"><Wallet :size="22" /></div>
        <h3>Sin cobros registrados</h3>
        <p>Aquí quedará el historial de cobros a clientes.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr><th>Número</th><th>Cliente</th><th>Método</th><th class="num">Monto</th><th>Aplicado a</th><th>Fecha</th><th>Cajero</th><th class="acciones-col"></th></tr>
          </thead>
          <tbody>
            <tr v-for="p in pagos" :key="p.id" :class="p.anulado_at ? 'anulado' : ''">
              <td class="mono">{{ p.numero }}</td>
              <td>{{ p.cliente }}</td>
              <td>{{ capitalizar(p.metodo) }}</td>
              <td class="num mono">{{ fmtSoles(p.monto) }}</td>
              <td>
                <span v-for="a in p.aplicaciones" :key="a.comprobante_id" class="tag mono">{{ a.numero }}</span>
                <span v-if="!p.aplicaciones?.length" class="muted">A cuenta</span>
              </td>
              <td class="mono">{{ fmtFechaHora(p.fecha_pago) }}</td>
              <td class="muted">{{ p.cajero || "—" }}</td>
              <td class="acciones-col">
                <button v-if="puedeAnular && !p.anulado_at" class="btn mini" title="Anular" @click="anular(p)">
                  <Ban :size="13" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue";
import {
  CreditCard, Wallet, AlertTriangle, Clock, BarChart3, CheckCircle2,
  RefreshCw, Ban,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { facturacionApi } from "../../facturacion/api/facturacion.api.js";
import { pagosApi } from "../api/pagos.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtSoles, fmtDate } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const { hasPermission } = useAuth();
const puedeCobrar = computed(() => hasPermission("pagos:registrar"));
const puedeAnular = computed(() => hasPermission("pagos:anular"));

const cuentas = ref([]);
const resumen = ref({});
const pagos = ref([]);
const cargando = ref(false);

const pctVencido = computed(() => {
  const t = Number(resumen.value.total_deuda ?? 0);
  return t ? Math.round((Number(resumen.value.vencido) / t) * 100) : 0;
});

const hoyISO = new Date().toISOString().slice(0, 10);
const pagosHoy = computed(() =>
  pagos.value.filter((p) => !p.anulado_at && String(p.fecha_pago).slice(0, 10) === hoyISO),
);
const cobradoHoy = computed(() => pagosHoy.value.reduce((s, p) => s + Number(p.monto), 0));

/** Tramos de antigüedad, con su participación sobre el total. */
const tramos = computed(() => {
  const defs = [
    { key: "por_vencer", label: "Por vencer", tone: "ok" },
    { key: "1_30", label: "1 a 30 días", tone: "info" },
    { key: "31_60", label: "31 a 60 días", tone: "warn" },
    { key: "61_90", label: "61 a 90 días", tone: "warn" },
    { key: "mas_90", label: "Más de 90 días", tone: "danger" },
  ];
  const total = cuentas.value.reduce((s, c) => s + Number(c.saldo_pendiente), 0) || 1;
  return defs.map((d) => {
    const filas = cuentas.value.filter((c) => c.tramo === d.key);
    const monto = filas.reduce((s, c) => s + Number(c.saldo_pendiente), 0);
    return { ...d, monto, docs: filas.length, pct: Math.round((monto / total) * 100) };
  });
});

function toneTramo(t) {
  return { por_vencer: "ok", "1_30": "info", "31_60": "warn", "61_90": "warn", mas_90: "danger" }[t] || "neutral";
}
function labelTramo(t) {
  return { por_vencer: "Al día", "1_30": "1–30 d", "31_60": "31–60 d", "61_90": "61–90 d", mas_90: "+90 d" }[t] || t;
}

async function cobrar(c) {
  const monto = await notify.prompt(`Cobrar ${c.numero_completo}`, {
    text: `${c.cliente} · saldo ${fmtSoles(c.saldo_pendiente)}`,
    inputType: "number",
    defaultValue: String(c.saldo_pendiente),
  });
  if (!monto) return;

  const metodo = await notify.select("Método de pago", [
    { value: "efectivo", label: "Efectivo" },
    { value: "tarjeta", label: "Tarjeta" },
    { value: "yape", label: "Yape" },
    { value: "plin", label: "Plin" },
    { value: "transferencia", label: "Transferencia" },
  ], "efectivo");
  if (!metodo) return;

  try {
    await pagosApi.registrar({
      cliente_id: c.cliente_id,
      monto: Number(monto),
      metodo,
      aplicaciones: [{ comprobante_id: c.id, monto: Number(monto) }],
    });
    notify.success("Cobro registrado");
    cargar();
  } catch (e) {
    notify.error("No se pudo registrar el cobro", e.message);
  }
}

async function anular(p) {
  const motivo = await notify.prompt(`Anular cobro ${p.numero}`, {
    placeholder: "Motivo de la anulación",
  });
  if (!motivo) return;
  try {
    await pagosApi.anular(p.id, motivo);
    notify.success("Cobro anulado");
    cargar();
  } catch (e) {
    notify.error("No se pudo anular", e.message);
  }
}

async function cargar() {
  cargando.value = true;
  try {
    const [cxc, pg] = await Promise.all([
      facturacionApi.cuentasPorCobrar(),
      pagosApi.listar({ pageSize: 30 }),
    ]);
    cuentas.value = cxc.data ?? [];
    resumen.value = cxc.meta ?? {};
    pagos.value = pg.data ?? [];
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.deuda { color: var(--red-ink); font-weight: 600; }
.anulado { opacity: 0.5; text-decoration: line-through; }

.aging { display: flex; flex-direction: column; gap: 12px; }
.aging-item { display: grid; grid-template-columns: 130px 110px 1fr 70px; align-items: center; gap: 12px; }
.aging-item .l { font-size: 12.5px; color: var(--ink-2); }
.aging-item .n { font-size: 12.5px; color: var(--ink); text-align: right; }
.aging-item .d { font-size: 11.5px; color: var(--ink-4); text-align: right; }
.aging-item .barra { height: 8px; border-radius: 999px; background: var(--bg-soft); overflow: hidden; }
.aging-item .fill { height: 100%; border-radius: 999px; }
.aging-item .fill.ok { background: var(--emerald); }
.aging-item .fill.info { background: var(--blue); }
.aging-item .fill.warn { background: var(--amber); }
.aging-item .fill.danger { background: var(--red); }

.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
</style>
