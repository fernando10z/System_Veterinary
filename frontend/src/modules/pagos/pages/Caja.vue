<template>
  <div>
    <PageHeader
      eyebrow="Administración"
      title="Caja"
      :subtitle="caja ? `Turno abierto desde ${fmtFechaHora(caja.fecha_apertura)}` : 'Sin caja abierta'"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
        <button v-if="puedeOperar && !caja" class="btn primary" @click="modalAbrir = true">
          <Unlock :size="14" /> Abrir caja
        </button>
        <template v-else-if="puedeOperar && caja">
          <button class="btn" @click="modalMovimiento = true"><Plus :size="14" /> Movimiento</button>
          <button class="btn primary" @click="abrirCierre"><Lock :size="14" /> Cerrar caja</button>
        </template>
      </template>
    </PageHeader>

    <!-- ---------- Turno abierto ---------- -->
    <template v-if="caja">
      <div class="stat-row">
        <div class="stat">
          <div class="stat-label">Apertura <span class="icon-tile"><Wallet :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(caja.monto_apertura) }}</div>
          <div class="stat-meta">{{ fmtFechaHora(caja.fecha_apertura) }}</div>
        </div>
        <div class="stat">
          <div class="stat-label">Ingresos <span class="icon-tile"><ArrowDownLeft :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(caja.ingresos) }}</div>
          <div class="stat-meta"><span class="trend">{{ caja.movimientos }}</span> movimientos</div>
        </div>
        <div class="stat">
          <div class="stat-label">Egresos <span class="icon-tile amber"><ArrowUpRight :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(caja.egresos) }}</div>
          <div class="stat-meta">salidas del turno</div>
        </div>
        <div class="stat">
          <div class="stat-label">Efectivo esperado <span class="icon-tile violet"><Banknote :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(efectivoEsperado) }}</div>
          <div class="stat-meta">debe estar en la caja</div>
        </div>
      </div>

      <section class="module-panel">
        <header class="module-panel-head">
          <h2>
            <span class="head-icon"><ListOrdered :size="14" /></span>
            Movimientos del turno
            <span class="head-meta">{{ (caja.detalle ?? []).length }}</span>
          </h2>
        </header>

        <div v-if="!(caja.detalle ?? []).length" class="module-panel-body module-empty">
          <div class="empty-icon"><ListOrdered :size="22" /></div>
          <h3>Sin movimientos aún</h3>
          <p>Los cobros del día entrarán aquí automáticamente.</p>
        </div>

        <div v-else class="module-panel-body tabla-wrap">
          <table>
            <thead>
              <tr><th>Hora</th><th>Concepto</th><th>Método</th><th>Tipo</th><th class="num">Monto</th></tr>
            </thead>
            <tbody>
              <tr v-for="m in caja.detalle" :key="m.id">
                <td class="mono">{{ fmtHora(m.fecha) }}</td>
                <td>{{ m.concepto }}</td>
                <td>{{ capitalizar(m.metodo) }}</td>
                <td>
                  <span :class="['estado-pill', m.tipo === 'ingreso' ? 'ok' : 'danger']">
                    <span class="dot"></span>{{ capitalizar(m.tipo) }}
                  </span>
                </td>
                <td class="num mono">{{ m.tipo === "ingreso" ? "+" : "−" }}{{ fmtSoles(m.monto) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>

    <div v-else-if="!cargando" class="module-panel">
      <div class="module-panel-body module-empty">
        <div class="empty-icon"><Wallet :size="22" /></div>
        <h3>No tienes una caja abierta</h3>
        <p>Abre la caja al iniciar tu turno para que los cobros queden registrados en el arqueo.</p>
        <button v-if="puedeOperar" class="btn primary" style="margin-top: 6px" @click="modalAbrir = true">
          <Unlock :size="14" /> Abrir caja
        </button>
      </div>
    </div>

    <!-- ---------- Historial de arqueos ---------- -->
    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><History :size="14" /></span>
          Arqueos anteriores
          <span class="head-meta">{{ historial.length }}</span>
        </h2>
      </header>

      <div v-if="!historial.length" class="module-panel-body module-empty">
        <div class="empty-icon"><History :size="22" /></div>
        <h3>Sin arqueos registrados</h3>
        <p>Al cerrar una caja quedará el registro aquí.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Caja</th><th>Apertura</th><th>Cierre</th><th>Responsable</th>
              <th class="num">Esperado</th><th class="num">Contado</th><th class="num">Diferencia</th><th>Estado</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="h in historial" :key="h.id">
              <td class="mono">{{ h.numero }}</td>
              <td class="mono">{{ fmtFechaHora(h.fecha_apertura) }}</td>
              <td class="mono">{{ h.fecha_cierre ? fmtFechaHora(h.fecha_cierre) : "—" }}</td>
              <td>{{ h.abierta_por }}</td>
              <td class="num mono">{{ fmtSoles(h.monto_esperado) }}</td>
              <td class="num mono">{{ h.monto_contado != null ? fmtSoles(h.monto_contado) : "—" }}</td>
              <td class="num mono">
                <span :class="diferenciaTone(h.diferencia)">
                  {{ h.diferencia != null ? fmtSoles(h.diferencia) : "—" }}
                </span>
              </td>
              <td>
                <span :class="['estado-pill', toneCaja(h.estado)]">
                  <span class="dot"></span>{{ capitalizar(h.estado) }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- ---------- Modal: abrir caja ---------- -->
    <div v-if="modalAbrir" class="modal-back" @click="modalAbrir = false">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Abrir caja</h3></div>
        <div class="m-body">
          <div v-if="error" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ error }}</span>
          </div>
          <div class="field">
            <label>Monto de apertura (S/)</label>
            <input v-model.number="apertura.monto_apertura" type="number" min="0" step="0.10" />
            <small class="muted">Efectivo con el que inicias el turno.</small>
          </div>
          <div class="field">
            <label>Observaciones</label>
            <textarea v-model="apertura.observaciones" rows="2"></textarea>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalAbrir = false">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="abrirCaja">
            {{ guardando ? "Abriendo…" : "Abrir caja" }}
          </button>
        </div>
      </div>
    </div>

    <!-- ---------- Modal: movimiento ---------- -->
    <div v-if="modalMovimiento" class="modal-back" @click="modalMovimiento = false">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Movimiento de caja</h3></div>
        <div class="m-body">
          <div class="form-grid">
            <div class="field">
              <label>Tipo</label>
              <select v-model="mov.tipo">
                <option value="ingreso">Ingreso</option>
                <option value="egreso">Egreso</option>
              </select>
            </div>
            <div class="field">
              <label>Método</label>
              <select v-model="mov.metodo">
                <option value="efectivo">Efectivo</option>
                <option value="tarjeta">Tarjeta</option>
                <option value="yape">Yape</option>
                <option value="plin">Plin</option>
                <option value="transferencia">Transferencia</option>
              </select>
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Concepto <span class="req">*</span></label>
              <input v-model.trim="mov.concepto" type="text" placeholder="Compra de insumos de limpieza" />
            </div>
            <div class="field">
              <label>Monto (S/) <span class="req">*</span></label>
              <input v-model.number="mov.monto" type="number" min="0.01" step="0.01" />
            </div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalMovimiento = false">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="registrarMovimiento">
            {{ guardando ? "Registrando…" : "Registrar" }}
          </button>
        </div>
      </div>
    </div>

    <!-- ---------- Modal: cierre / arqueo ---------- -->
    <div v-if="modalCerrar" class="modal-back" @click="modalCerrar = false">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Arqueo de caja</h3></div>
        <div class="m-body">
          <div v-if="error" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ error }}</span>
          </div>

          <div class="arqueo-resumen">
            <div><span>Apertura</span><span class="mono">{{ fmtSoles(caja?.monto_apertura) }}</span></div>
            <div><span>Efectivo del turno</span><span class="mono">{{ fmtSoles(caja?.efectivo) }}</span></div>
            <div class="total"><span>Efectivo esperado</span><span class="mono">{{ fmtSoles(efectivoEsperado) }}</span></div>
          </div>

          <div class="field" style="margin-top: 14px">
            <label>Efectivo contado (S/) <span class="req">*</span></label>
            <input v-model.number="cierre.monto_contado" type="number" min="0" step="0.10" />
          </div>

          <div v-if="diferenciaPrevia !== null" :class="['dif-aviso', diferenciaPrevia === 0 ? 'ok' : 'warn']">
            <component :is="diferenciaPrevia === 0 ? CheckCircle2 : AlertTriangle" :size="15" />
            <span v-if="diferenciaPrevia === 0">La caja cuadra exactamente.</span>
            <span v-else>
              Diferencia de {{ fmtSoles(Math.abs(diferenciaPrevia)) }}
              ({{ diferenciaPrevia > 0 ? "sobrante" : "faltante" }}).
            </span>
          </div>

          <div class="field">
            <label>Observaciones del cierre</label>
            <textarea v-model="cierre.observaciones" rows="2"></textarea>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalCerrar = false">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="cerrarCaja">
            {{ guardando ? "Cerrando…" : "Cerrar caja" }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  Wallet, Unlock, Lock, Plus, RefreshCw, ListOrdered, History, Banknote,
  ArrowDownLeft, ArrowUpRight, AlertCircle, AlertTriangle, CheckCircle2,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { cajaApi } from "../api/pagos.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtSoles } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, fmtHora, capitalizar } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const { hasPermission } = useAuth();
const puedeOperar = computed(() => hasPermission("caja:operar"));

const caja = ref(null);
const historial = ref([]);
const cargando = ref(false);
const guardando = ref(false);
const error = ref("");

const modalAbrir = ref(false);
const modalMovimiento = ref(false);
const modalCerrar = ref(false);

const apertura = reactive({ monto_apertura: 0, observaciones: "" });
const mov = reactive({ tipo: "egreso", metodo: "efectivo", concepto: "", monto: 0 });
const cierre = reactive({ monto_contado: 0, observaciones: "" });

/** Solo el efectivo debe estar físicamente en la caja al cerrar. */
const efectivoEsperado = computed(() =>
  caja.value ? Number(caja.value.monto_apertura) + Number(caja.value.efectivo) : 0,
);
const diferenciaPrevia = computed(() => {
  if (!modalCerrar.value || cierre.monto_contado === null) return null;
  return Math.round((Number(cierre.monto_contado) - efectivoEsperado.value) * 100) / 100;
});

function toneCaja(e) {
  return { abierta: "info", cerrada: "warn", cuadrada: "ok" }[e] || "neutral";
}
function diferenciaTone(d) {
  if (d === null || d === undefined) return "muted";
  return Number(d) === 0 ? "" : "deuda";
}

function abrirCierre() {
  error.value = "";
  cierre.monto_contado = efectivoEsperado.value;
  cierre.observaciones = "";
  modalCerrar.value = true;
}

async function abrirCaja() {
  error.value = "";
  guardando.value = true;
  try {
    await cajaApi.abrir({ ...apertura });
    modalAbrir.value = false;
    cargar();
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

async function registrarMovimiento() {
  if (!mov.concepto || !mov.monto) return;
  guardando.value = true;
  try {
    await cajaApi.movimiento({ ...mov });
    modalMovimiento.value = false;
    Object.assign(mov, { tipo: "egreso", metodo: "efectivo", concepto: "", monto: 0 });
    cargar();
  } catch (e) {
    notify.error("No se pudo registrar el movimiento", e.message);
  } finally {
    guardando.value = false;
  }
}

async function cerrarCaja() {
  error.value = "";
  guardando.value = true;
  try {
    const r = await cajaApi.cerrar(caja.value.id, { ...cierre });
    modalCerrar.value = false;
    const d = r.data;
    if (d.cuadrada) notify.success("Caja cerrada y cuadrada");
    else notify.warn("Caja cerrada con diferencia", `${fmtSoles(d.diferencia)}`);
    cargar();
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

async function cargar() {
  cargando.value = true;
  try {
    const [actual, hist] = await Promise.all([cajaApi.actual(), cajaApi.listar()]);
    caja.value = actual.data;
    historial.value = (hist.data ?? []).filter((h) => h.estado !== "abierta");
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.deuda { color: var(--red-ink); font-weight: 600; }
.arqueo-resumen { display: flex; flex-direction: column; gap: 7px; }
.arqueo-resumen > div { display: flex; justify-content: space-between; font-size: 13px; color: var(--ink-2); }
.arqueo-resumen .total {
  border-top: 1px solid var(--line); padding-top: 8px;
  font-size: 15px; font-weight: 700; color: var(--ink);
}
.dif-aviso {
  display: flex; align-items: center; gap: 8px;
  padding: 9px 11px; border-radius: 9px; margin-bottom: 12px; font-size: 12.5px;
}
.dif-aviso.ok { background: var(--emerald-soft); color: var(--emerald-ink); }
.dif-aviso.warn { background: var(--amber-soft); color: var(--amber-ink); }
.req { color: var(--red); }
</style>
