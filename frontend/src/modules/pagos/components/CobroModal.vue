<template>
  <div class="modal-back" v-dialogo.estricto="cerrar">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head">
        <h3>Registrar cobro <span v-if="comprobante.numero_completo" class="codigo muted">{{ comprobante.numero_completo }}</span></h3>
      </div>

      <div class="m-body">
        <div class="saldo-box">
          <div>
            <div class="k">{{ comprobante.cliente || "Cliente" }}</div>
            <div class="muted">Saldo pendiente</div>
          </div>
          <div class="v cifra">{{ fmtSoles(saldo) }}</div>
        </div>

        <div v-if="error" class="callout danger" style="margin: 12px 0 0">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <div v-for="(m, i) in medios" :key="m.key" :class="['medio', { pagado: m.pagado }]">
          <div class="medio-head">
            <strong>{{ medios.length > 1 ? `Medio ${i + 1}` : "Medio de pago" }}</strong>
            <span v-if="m.pagado" class="estado-pill ok"><span class="dot"></span>Registrado</span>
            <button
              v-else-if="medios.length > 1"
              class="btn ghost sm"
              type="button"
              :disabled="enCurso"
              aria-label="Quitar este medio de pago"
              @click="quitar(i)"
            >
              <X :size="14" /> Quitar
            </button>
          </div>

          <div class="metodos" role="radiogroup" :aria-label="`Método del medio ${i + 1}`">
            <button
              v-for="op in METODOS"
              :key="op.value"
              type="button"
              role="radio"
              :aria-checked="m.metodo === op.value"
              :class="['metodo', { activo: m.metodo === op.value }]"
              :disabled="m.pagado || enCurso"
              @click="m.metodo = op.value"
            >
              <component :is="op.icon" :size="15" /> {{ op.label }}
            </button>
          </div>

          <div class="form-grid">
            <div class="field">
              <label :for="`cobro-monto-${i}`">Monto (S/) <span class="req">*</span></label>
              <input
                :id="`cobro-monto-${i}`" v-model.number="m.monto" type="number" min="0.01" step="0.01"
                inputmode="decimal" :disabled="m.pagado || enCurso" :class="{ invalid: m.errMonto }"
              />
              <small v-if="m.errMonto" class="field-error">{{ m.errMonto }}</small>
            </div>

            <div v-if="m.metodo !== 'efectivo'" class="field">
              <label :for="`cobro-ref-${i}`">N.º de operación <span class="req">*</span></label>
              <input
                :id="`cobro-ref-${i}`" v-model.trim="m.referencia" type="text" maxlength="120"
                :placeholder="m.metodo === 'tarjeta' ? 'Voucher / lote' : 'Código de la operación'"
                :disabled="m.pagado || enCurso" :class="{ invalid: m.errRef }"
              />
              <small v-if="m.errRef" class="field-error">{{ m.errRef }}</small>
            </div>

            <!-- Vuelto: solo tiene sentido con efectivo -->
            <div v-else class="field">
              <label :for="`cobro-recibido-${i}`">Recibido (S/)</label>
              <input
                :id="`cobro-recibido-${i}`" v-model.number="m.recibido" type="number" min="0" step="0.10"
                inputmode="decimal" placeholder="Con cuánto paga" :disabled="m.pagado || enCurso"
              />
              <div v-if="!m.pagado" class="rapidos">
                <button
                  v-for="b in billetesSugeridos(m.monto)" :key="b" type="button" class="btn sm"
                  :disabled="enCurso" @click="m.recibido = b"
                >{{ b === Number(m.monto) ? "Exacto" : `S/ ${b}` }}</button>
              </div>
            </div>
          </div>

          <div v-if="m.metodo === 'efectivo' && Number(m.recibido) > 0" :class="['vuelto', vuelto(m) < 0 ? 'falta' : '']">
            <template v-if="vuelto(m) >= 0">Vuelto: <strong class="cifra">{{ fmtSoles(vuelto(m)) }}</strong></template>
            <template v-else>Faltan <strong class="cifra">{{ fmtSoles(-vuelto(m)) }}</strong> para cubrir el monto</template>
          </div>
        </div>

        <div class="pie-medios">
          <button
            v-if="restante > 0.009 && !enCurso"
            type="button" class="btn sm"
            @click="agregarMedio"
          >
            <Plus :size="13" /> Pagar el resto con otro medio
          </button>
          <div class="resumen">
            <span>Total a cobrar</span>
            <strong class="cifra">{{ fmtSoles(totalMedios) }}</strong>
            <span v-if="restante > 0.009" class="muted">· queda {{ fmtSoles(restante) }} pendiente</span>
          </div>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" type="button" :disabled="enCurso" @click="cerrar">
          {{ algunoPagado ? "Cerrar" : "Cancelar" }}
        </button>
        <button class="btn primary" type="button" :disabled="enCurso || !pendientes.length" @click="registrar">
          <Loader2 v-if="enCurso" :size="14" class="spin" />
          {{ enCurso ? "Registrando…" : `Cobrar ${fmtSoles(totalPendiente)}` }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, computed } from "vue";
import {
  AlertCircle, Banknote, CreditCard, Smartphone, Landmark, Plus, X, Loader2,
} from "lucide-vue-next";
import { pagosApi } from "../api/pagos.api.js";
import { fmtSoles } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";
import { uuid } from "../../../shared/utils/uuid.js";

/**
 * Cobro de un comprobante: uno o varios medios (pago partido). Cada medio es
 * un POST /pagos independiente con su propia idempotency_key, generada una sola
 * vez al abrir el modal: un doble clic o un reintento tras un corte de red no
 * cobra dos veces. Si falla el segundo medio, el primero ya quedó registrado y
 * se muestra como tal; reintentar solo envía lo pendiente.
 */
const props = defineProps({
  /** { id, numero_completo, cliente_id, cliente, saldo_pendiente } */
  comprobante: { type: Object, required: true },
});
const emit = defineEmits(["close", "cobrado"]);

const METODOS = [
  { value: "efectivo", label: "Efectivo", icon: Banknote },
  { value: "yape", label: "Yape", icon: Smartphone },
  { value: "plin", label: "Plin", icon: Smartphone },
  { value: "tarjeta", label: "Tarjeta", icon: CreditCard },
  { value: "transferencia", label: "Transferencia", icon: Landmark },
];

const redondear = (n) => Math.round((Number(n) || 0) * 100) / 100;
const saldo = computed(() => redondear(props.comprobante.saldo_pendiente));

function nuevoMedio(monto, metodo = "efectivo") {
  return {
    key: uuid(), // también es la idempotency_key de este medio
    metodo, monto: redondear(monto), referencia: "", recibido: null,
    pagado: false, errMonto: "", errRef: "",
  };
}

const medios = reactive([nuevoMedio(props.comprobante.saldo_pendiente)]);
const enCurso = ref(false);
const error = ref("");

const totalMedios = computed(() => redondear(medios.reduce((a, m) => a + (Number(m.monto) || 0), 0)));
const restante = computed(() => redondear(saldo.value - totalMedios.value));
const pendientes = computed(() => medios.filter((m) => !m.pagado));
const totalPendiente = computed(() => redondear(pendientes.value.reduce((a, m) => a + (Number(m.monto) || 0), 0)));
const algunoPagado = computed(() => medios.some((m) => m.pagado));

function vuelto(m) {
  return redondear(Number(m.recibido) - Number(m.monto));
}

/** Monto exacto y los billetes que suelen entregar para pagar ese monto. */
function billetesSugeridos(monto) {
  const n = Number(monto) || 0;
  if (n <= 0) return [];
  const out = [n];
  for (const b of [10, 20, 50, 100, 200]) {
    if (b > n && out.length < 4) out.push(b);
  }
  return [...new Set(out)];
}

function agregarMedio() {
  // El segundo medio arranca por lo que falta y con otro método: el caso
  // típico es "una parte en efectivo y el resto por Yape".
  medios.push(nuevoMedio(restante.value, medios[0]?.metodo === "efectivo" ? "yape" : "efectivo"));
}

function quitar(i) {
  medios.splice(i, 1);
}

function validar() {
  let ok = true;
  for (const m of pendientes.value) {
    m.errMonto = "";
    m.errRef = "";
    if (!(Number(m.monto) > 0)) { m.errMonto = "El monto debe ser mayor a cero."; ok = false; }
    if (m.metodo !== "efectivo" && !m.referencia) {
      m.errRef = "Indica el número de operación."; ok = false;
    }
  }
  if (restante.value < -0.009) {
    error.value = `El total (${fmtSoles(totalMedios.value)}) supera el saldo del comprobante (${fmtSoles(saldo.value)}).`;
    ok = false;
  }
  return ok;
}

async function registrar() {
  if (enCurso.value) return;
  error.value = "";
  if (!validar()) return;

  enCurso.value = true;
  try {
    // Secuencial: si un medio falla, los anteriores ya quedaron cobrados y el
    // reintento envía solo lo pendiente (con las mismas claves).
    for (const m of pendientes.value) {
      await pagosApi.registrar({
        cliente_id: props.comprobante.cliente_id,
        monto: redondear(m.monto),
        metodo: m.metodo,
        ...(m.referencia ? { referencia: m.referencia } : {}),
        aplicaciones: [{ comprobante_id: props.comprobante.id, monto: redondear(m.monto) }],
        idempotency_key: m.key,
      });
      m.pagado = true;
    }
    const vueltoTotal = medios
      .filter((m) => m.metodo === "efectivo" && Number(m.recibido) > 0)
      .reduce((a, m) => a + Math.max(0, vuelto(m)), 0);
    notify.success(
      "Cobro registrado",
      vueltoTotal > 0 ? `Vuelto: ${fmtSoles(vueltoTotal)}` : `${fmtSoles(totalMedios.value)} cobrados`,
    );
    emit("cobrado", { monto: totalMedios.value });
  } catch (e) {
    error.value = algunoPagado.value
      ? `Se registró parte del cobro, pero falló un medio: ${e.message}. Reintenta: solo se enviará lo pendiente.`
      : e.message;
  } finally {
    enCurso.value = false;
  }
}

function cerrar() {
  if (enCurso.value) return;
  // Si ya se registró parte, el padre debe recargar el saldo.
  if (algunoPagado.value) emit("cobrado", { parcial: true });
  else emit("close");
}
</script>

<style scoped>
.saldo-box {
  display: flex; justify-content: space-between; align-items: center; gap: 12px;
  padding: 12px 14px; border-radius: 10px;
  background: var(--emerald-soft); border: 1px solid var(--emerald-line);
}
.saldo-box .k { font-weight: 600; color: var(--ink); }
.saldo-box .v { font-family: var(--font-display); font-variant-numeric: tabular-nums; font-size: 22px; font-weight: 700; color: var(--ink); }
.medio { margin-top: 14px; padding: 12px; border: 1px solid var(--line); border-radius: 10px; }
.medio.pagado { opacity: 0.7; background: var(--bg-soft); }
.medio-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 10px; }
.metodos { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 12px; }
.metodo {
  display: inline-flex; align-items: center; gap: 6px;
  min-height: 40px; padding: 0 12px; border-radius: 8px;
  border: 1px solid var(--line); background: var(--bg-elev); color: var(--ink-2);
  font-size: 13px; font-weight: 500;
}
.metodo:hover:not([disabled]) { border-color: var(--line-strong); }
.metodo.activo { border-color: var(--emerald); background: var(--emerald-soft); color: var(--emerald-ink); font-weight: 600; }
.metodo[disabled] { cursor: not-allowed; }
.rapidos { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 6px; }
.vuelto {
  margin-top: 10px; padding: 8px 11px; border-radius: 8px;
  background: var(--emerald-soft); color: var(--emerald-ink); font-size: 13px;
}
.vuelto.falta { background: var(--amber-soft); color: var(--amber-ink); }
.pie-medios { display: flex; justify-content: space-between; align-items: center; gap: 10px; flex-wrap: wrap; margin-top: 14px; }
.resumen { margin-left: auto; display: flex; gap: 8px; align-items: baseline; font-size: 13px; flex-wrap: wrap; }
.resumen strong { font-size: 16px; }
.req { color: var(--red); }
</style>
