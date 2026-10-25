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
          <button class="btn" @click="abrirMovimiento"><Plus :size="14" /> Movimiento</button>
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
        <!-- Arqueo a ciegas: el esperado no se muestra mientras el turno está
             abierto; se revela recién en el cierre, después del conteo. -->
        <div class="stat">
          <div class="stat-label">Efectivo esperado <span class="icon-tile violet"><Banknote :size="14" /></span></div>
          <div class="stat-val muted">••••</div>
          <div class="stat-meta">se revela al registrar el conteo</div>
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
                <td class="cifra">{{ fmtHora(m.fecha) }}</td>
                <td>{{ m.concepto }}</td>
                <td>{{ capitalizar(m.metodo) }}</td>
                <td>
                  <span :class="['estado-pill', m.tipo === 'ingreso' ? 'ok' : 'danger']">
                    <span class="dot"></span>{{ capitalizar(m.tipo) }}
                  </span>
                </td>
                <td class="num cifra">{{ m.tipo === "ingreso" ? "+" : "−" }}{{ fmtSoles(m.monto) }}</td>
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
              <td class="codigo">{{ h.numero }}</td>
              <td class="cifra">{{ fmtFechaHora(h.fecha_apertura) }}</td>
              <td class="cifra">{{ h.fecha_cierre ? fmtFechaHora(h.fecha_cierre) : "—" }}</td>
              <td>{{ h.abierta_por }}</td>
              <td class="num cifra">{{ fmtSoles(h.monto_esperado) }}</td>
              <td class="num cifra">{{ h.monto_contado != null ? fmtSoles(h.monto_contado) : "—" }}</td>
              <td class="num cifra">
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
    <div v-if="modalAbrir" class="modal-back" v-dialogo="() => (modalAbrir = false)">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Abrir caja</h3></div>
        <div class="m-body">
          <div v-if="error" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ error }}</span>
          </div>
          <div class="field">
            <label for="caja-apertura">Monto de apertura (S/)</label>
            <input id="caja-apertura" v-model.number="apertura.monto_apertura" type="number" min="0" step="0.10" inputmode="decimal" />
            <small class="muted">Efectivo con el que inicias el turno.</small>
          </div>
          <div class="field">
            <label for="caja-apertura-obs">Observaciones</label>
            <textarea id="caja-apertura-obs" v-model="apertura.observaciones" rows="2"></textarea>
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
    <div v-if="modalMovimiento" class="modal-back" v-dialogo="() => (modalMovimiento = false)">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Movimiento de caja</h3></div>
        <div class="m-body">
          <div v-if="errorMov" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ errorMov }}</span>
          </div>
          <div class="form-grid">
            <div class="field">
              <label for="mov-tipo">Tipo</label>
              <select id="mov-tipo" v-model="mov.tipo">
                <option value="ingreso">Ingreso</option>
                <option value="egreso">Egreso</option>
              </select>
            </div>
            <div class="field">
              <label for="mov-metodo">Método</label>
              <select id="mov-metodo" v-model="mov.metodo">
                <option value="efectivo">Efectivo</option>
                <option value="tarjeta">Tarjeta</option>
                <option value="yape">Yape</option>
                <option value="plin">Plin</option>
                <option value="transferencia">Transferencia</option>
              </select>
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label for="mov-concepto">Concepto <span class="req">*</span></label>
              <input
                id="mov-concepto" v-model.trim="mov.concepto" type="text" maxlength="255"
                placeholder="Compra de insumos de limpieza"
                :class="{ invalid: movErrores.concepto }"
              />
              <small v-if="movErrores.concepto" class="field-error">{{ movErrores.concepto }}</small>
            </div>
            <div class="field">
              <label for="mov-monto">Monto (S/) <span class="req">*</span></label>
              <input
                id="mov-monto" v-model.number="mov.monto" type="number" min="0.01" step="0.01"
                inputmode="decimal" :class="{ invalid: movErrores.monto }"
              />
              <small v-if="movErrores.monto" class="field-error">{{ movErrores.monto }}</small>
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

    <!-- ---------- Modal: cierre / arqueo a ciegas ---------- -->
    <!-- El cajero cuenta SIN ver cuánto debería haber. El esperado y la
         diferencia aparecen recién después de registrar el conteo; si recuenta,
         el primer conteo queda en las observaciones del cierre. -->
    <div v-if="modalCerrar" class="modal-back" v-dialogo.estricto="() => (modalCerrar = false)">
      <div class="modal modal-wide" @click.stop>
        <div class="m-head"><h3>Arqueo de caja</h3></div>
        <div class="m-body">
          <div v-if="error" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ error }}</span>
          </div>

          <!-- Paso 1: conteo a ciegas -->
          <template v-if="!conteoRegistrado">
            <p class="muted" style="margin: 0 0 12px">
              Cuenta el efectivo físico de la caja y registra el total. El sistema te mostrará
              lo esperado recién después del conteo.
            </p>

            <label class="check-line">
              <input v-model="usarDenominaciones" type="checkbox" />
              Contar por billetes y monedas
            </label>

            <div v-if="usarDenominaciones" class="denoms">
              <div v-for="d in DENOMINACIONES" :key="d.valor" class="denom">
                <label :for="`den-${d.valor}`">{{ d.label }}</label>
                <input
                  :id="`den-${d.valor}`" v-model.number="conteo[d.valor]" type="number"
                  min="0" step="1" inputmode="numeric" placeholder="0"
                />
                <span class="cifra muted">{{ fmtSoles(d.valor * (Number(conteo[d.valor]) || 0)) }}</span>
              </div>
            </div>

            <div class="field" style="margin-top: 14px">
              <label for="caja-contado">Efectivo contado (S/) <span class="req">*</span></label>
              <input
                id="caja-contado" v-model="cierre.monto_contado" type="number" min="0" step="0.10"
                inputmode="decimal" placeholder="0.00" :readonly="usarDenominaciones"
                :class="{ invalid: errorConteo }" @keyup.enter="registrarConteo"
              />
              <small v-if="errorConteo" class="field-error">{{ errorConteo }}</small>
              <small v-else-if="usarDenominaciones" class="muted">Se calcula con las cantidades de arriba.</small>
            </div>
          </template>

          <!-- Paso 2: resultado del arqueo -->
          <template v-else>
            <div class="arqueo-resumen">
              <div><span>Apertura</span><span class="cifra">{{ fmtSoles(caja?.monto_apertura) }}</span></div>
              <div><span>Efectivo del turno</span><span class="cifra">{{ fmtSoles(caja?.efectivo) }}</span></div>
              <div class="total"><span>Efectivo esperado</span><span class="cifra">{{ fmtSoles(efectivoEsperado) }}</span></div>
              <div class="total"><span>Efectivo contado</span><span class="cifra">{{ fmtSoles(montoContado) }}</span></div>
            </div>

            <div :class="['dif-aviso', diferenciaPrevia === 0 ? 'ok' : 'warn']" style="margin-top: 12px">
              <component :is="diferenciaPrevia === 0 ? CheckCircle2 : AlertTriangle" :size="15" />
              <span v-if="diferenciaPrevia === 0">La caja cuadra exactamente.</span>
              <span v-else>
                Diferencia de {{ fmtSoles(Math.abs(diferenciaPrevia)) }}
                ({{ diferenciaPrevia > 0 ? "sobrante" : "faltante" }}).
              </span>
            </div>

            <div class="field">
              <label for="caja-obs-cierre">
                Observaciones del cierre <span v-if="diferenciaPrevia !== 0" class="req">*</span>
              </label>
              <textarea
                id="caja-obs-cierre" v-model="cierre.observaciones" rows="2"
                :placeholder="diferenciaPrevia !== 0 ? 'Explica la diferencia (obligatorio)' : ''"
                :class="{ invalid: errorObs }"
              ></textarea>
              <small v-if="errorObs" class="field-error">{{ errorObs }}</small>
            </div>
          </template>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" :disabled="guardando" @click="modalCerrar = false">Cancelar</button>
          <template v-if="!conteoRegistrado">
            <button class="btn primary" @click="registrarConteo">Registrar conteo</button>
          </template>
          <template v-else>
            <button class="btn" :disabled="guardando" @click="recontar">Volver a contar</button>
            <button class="btn primary" :disabled="guardando" @click="cerrarCaja">
              {{ guardando ? "Cerrando…" : "Cerrar caja" }}
            </button>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted } from "vue";
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
const cierre = reactive({ monto_contado: "", observaciones: "" });
const errorMov = ref("");
const movErrores = reactive({ concepto: "", monto: "" });

/** Billetes y monedas en circulación (PEN). */
const DENOMINACIONES = [
  { valor: 200, label: "S/ 200" }, { valor: 100, label: "S/ 100" }, { valor: 50, label: "S/ 50" },
  { valor: 20, label: "S/ 20" }, { valor: 10, label: "S/ 10" }, { valor: 5, label: "S/ 5" },
  { valor: 2, label: "S/ 2" }, { valor: 1, label: "S/ 1" }, { valor: 0.5, label: "S/ 0.50" },
  { valor: 0.2, label: "S/ 0.20" }, { valor: 0.1, label: "S/ 0.10" },
];
const usarDenominaciones = ref(false);
const conteo = reactive({});
const conteoRegistrado = ref(false);
const conteosPrevios = ref([]);
const errorConteo = ref("");
const errorObs = ref("");

const totalDenominaciones = computed(() =>
  Math.round(DENOMINACIONES.reduce((a, d) => a + d.valor * (Number(conteo[d.valor]) || 0), 0) * 100) / 100,
);
watch([totalDenominaciones, usarDenominaciones], () => {
  if (usarDenominaciones.value) cierre.monto_contado = totalDenominaciones.value;
});
const montoContado = computed(() =>
  cierre.monto_contado === "" || cierre.monto_contado === null ? null : Number(cierre.monto_contado),
);

/** Solo el efectivo debe estar físicamente en la caja al cerrar. */
const efectivoEsperado = computed(() =>
  caja.value ? Number(caja.value.monto_apertura) + Number(caja.value.efectivo) : 0,
);
const diferenciaPrevia = computed(() => {
  if (!conteoRegistrado.value || montoContado.value === null) return null;
  return Math.round((montoContado.value - efectivoEsperado.value) * 100) / 100;
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
  errorConteo.value = "";
  errorObs.value = "";
  // Conteo a ciegas: el campo arranca vacío, nunca con el esperado.
  cierre.monto_contado = "";
  cierre.observaciones = "";
  usarDenominaciones.value = false;
  for (const d of DENOMINACIONES) delete conteo[d.valor];
  conteoRegistrado.value = false;
  conteosPrevios.value = [];
  modalCerrar.value = true;
}

function registrarConteo() {
  errorConteo.value = "";
  const v = montoContado.value;
  if (v === null || Number.isNaN(v)) { errorConteo.value = "Ingresa el efectivo que contaste."; return; }
  if (v < 0) { errorConteo.value = "El monto no puede ser negativo."; return; }
  conteoRegistrado.value = true;
}

/** Un recuento queda registrado: el primer conteo no desaparece. */
function recontar() {
  conteosPrevios.value.push(montoContado.value);
  conteoRegistrado.value = false;
  errorObs.value = "";
}

function abrirMovimiento() {
  errorMov.value = "";
  movErrores.concepto = "";
  movErrores.monto = "";
  modalMovimiento.value = true;
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
  errorMov.value = "";
  movErrores.concepto = mov.concepto ? "" : "Indica el concepto del movimiento.";
  movErrores.monto = Number(mov.monto) > 0 ? "" : "El monto debe ser mayor a cero.";
  if (movErrores.concepto || movErrores.monto) return;
  if (guardando.value) return;
  guardando.value = true;
  try {
    await cajaApi.movimiento({ ...mov, monto: Number(mov.monto) });
    modalMovimiento.value = false;
    Object.assign(mov, { tipo: "egreso", metodo: "efectivo", concepto: "", monto: 0 });
    notify.toast("Movimiento registrado");
    cargar();
  } catch (e) {
    errorMov.value = e.message;
  } finally {
    guardando.value = false;
  }
}

async function cerrarCaja() {
  error.value = "";
  errorObs.value = "";
  const dif = diferenciaPrevia.value;
  if (dif === null) return;
  if (dif !== 0 && !cierre.observaciones.trim()) {
    errorObs.value = "Hay una diferencia: explica el motivo antes de cerrar.";
    return;
  }
  const ok = await notify.confirm(
    "¿Cerrar la caja?",
    dif === 0
      ? `Contado ${fmtSoles(montoContado.value)}. La caja cuadra.`
      : `Contado ${fmtSoles(montoContado.value)} · esperado ${fmtSoles(efectivoEsperado.value)} · `
        + `${dif > 0 ? "sobrante" : "faltante"} de ${fmtSoles(Math.abs(dif))}. El cierre no se puede deshacer.`,
    { confirmText: "Cerrar caja", icon: dif === 0 ? "question" : "warning" },
  );
  if (!ok) return;

  let observaciones = cierre.observaciones.trim();
  if (conteosPrevios.value.length) {
    const previos = conteosPrevios.value.map((v) => fmtSoles(v)).join(", ");
    observaciones = [observaciones, `Recuento: conteo(s) previo(s) ${previos}.`].filter(Boolean).join(" ");
  }
  guardando.value = true;
  try {
    const r = await cajaApi.cerrar(caja.value.id, {
      monto_contado: montoContado.value,
      ...(observaciones ? { observaciones } : {}),
    });
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
  } catch (e) {
    notify.error("No se pudo cargar la caja", e.message);
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
.check-line { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--ink-2); cursor: pointer; min-height: 32px; }
.denoms {
  display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 8px 12px; margin-top: 10px;
  padding: 12px; border: 1px solid var(--line); border-radius: 9px; background: var(--bg-sunken, var(--bg));
}
.denom { display: grid; grid-template-columns: 58px 1fr; gap: 2px 8px; align-items: center; }
.denom label { font-size: 12.5px; font-weight: 600; color: var(--ink-2); }
.denom input {
  border: 1px solid var(--line); border-radius: 7px; padding: 7px 8px; font-size: 13px;
  background: var(--bg-elev); color: var(--ink); width: 100%; min-height: 36px;
}
.denom span { grid-column: 2; font-size: 11px; }
</style>
