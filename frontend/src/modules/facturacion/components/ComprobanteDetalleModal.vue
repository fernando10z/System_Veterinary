<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal modal-doc" @click.stop>
      <div v-if="cargando" class="m-body">
        <span class="loading-mini"><Loader2 :size="14" class="spin" /> Cargando…</span>
      </div>

      <template v-else-if="c">
        <div class="m-head">
          <h3>{{ capitalizar(c.tipo) }} <span class="mono">{{ c.numero_completo }}</span></h3>
        </div>

        <div class="m-body">
          <!-- Cabecera del documento -->
          <div class="doc-head">
            <div>
              <div class="emisor">{{ c.emisor?.razon_social }}</div>
              <div class="muted">{{ c.emisor?.nombre_comercial }}</div>
              <div class="muted mono">RUC {{ c.emisor?.ruc }}</div>
              <div class="muted">{{ c.emisor?.direccion }}</div>
            </div>
            <div class="text-right">
              <span :class="['estado-pill', c.estado_pago === 'pagado' ? 'ok' : 'warn']">
                <span class="dot"></span>{{ capitalizar(c.estado_pago) }}
              </span>
              <div class="muted" style="margin-top: 6px">{{ fmtFechaHora(c.fecha_emision) }}</div>
            </div>
          </div>

          <div class="detalle-grid" style="margin: 16px 0">
            <div class="detalle-item">
              <div class="k">Cliente</div>
              <div class="v">{{ c.cliente?.razon_social || c.cliente?.nombre_completo }}</div>
            </div>
            <div class="detalle-item">
              <div class="k">Documento</div>
              <div class="v mono">{{ c.cliente?.tipo_documento }} {{ c.cliente?.numero_documento }}</div>
            </div>
            <div class="detalle-item">
              <div class="k">Paciente</div>
              <div class="v">{{ c.mascota || "—" }}</div>
            </div>
            <div class="detalle-item">
              <div class="k">Vencimiento</div>
              <div class="v">{{ c.fecha_vencimiento ? fmtDate(c.fecha_vencimiento) : "Contado" }}</div>
            </div>
          </div>

          <div class="tabla-wrap">
            <table>
              <thead>
                <tr>
                  <th>Descripción</th><th class="num">Cant.</th>
                  <th class="num">P. unit.</th><th class="num">IGV</th><th class="num">Total</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="i in c.items" :key="i.id">
                  <td>
                    <strong>{{ i.descripcion }}</strong>
                    <br /><small class="muted mono">{{ i.codigo || "" }}</small>
                  </td>
                  <td class="num mono">{{ i.cantidad }}</td>
                  <td class="num mono">{{ fmtSoles(i.precio_unitario) }}</td>
                  <td class="num mono">{{ fmtSoles(i.igv) }}</td>
                  <td class="num mono">{{ fmtSoles(i.total) }}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="totales">
            <div><span>Subtotal</span><span class="mono">{{ fmtSoles(c.subtotal) }}</span></div>
            <div><span>IGV</span><span class="mono">{{ fmtSoles(c.igv) }}</span></div>
            <div v-if="Number(c.descuento_global) > 0">
              <span>Descuento</span><span class="mono">− {{ fmtSoles(c.descuento_global) }}</span>
            </div>
            <div class="total"><span>Total</span><span class="mono">{{ fmtSoles(c.total) }}</span></div>
            <div v-if="Number(c.saldo_pendiente) > 0" class="saldo">
              <span>Saldo pendiente</span><span class="mono">{{ fmtSoles(c.saldo_pendiente) }}</span>
            </div>
          </div>

          <!-- Pagos aplicados -->
          <template v-if="(c.pagos ?? []).length">
            <div class="section-title" style="margin-top: 18px">Pagos aplicados</div>
            <div class="tabla-wrap" style="margin-top: 8px">
              <table>
                <thead><tr><th>Número</th><th>Método</th><th>Fecha</th><th class="num">Monto</th></tr></thead>
                <tbody>
                  <tr v-for="p in c.pagos" :key="p.id">
                    <td class="mono">{{ p.numero }}</td>
                    <td>{{ capitalizar(p.metodo) }}</td>
                    <td class="mono">{{ fmtFechaHora(p.fecha_pago) }}</td>
                    <td class="num mono">{{ fmtSoles(p.monto_aplicado) }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </template>
        </div>

        <div class="m-foot modal-actions">
          <button class="btn" @click="$emit('close')">Cerrar</button>
          <button class="btn" @click="imprimir"><Printer :size="14" /> Imprimir</button>
          <button
            v-if="puedeCobrar && Number(c.saldo_pendiente) > 0"
            class="btn primary"
            @click="cobrar"
          >
            <Wallet :size="14" /> Registrar cobro
          </button>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue";
import { Loader2, Printer, Wallet } from "lucide-vue-next";
import { facturacionApi } from "../api/facturacion.api.js";
import { pagosApi } from "../../pagos/api/pagos.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtSoles, fmtDate } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const props = defineProps({ comprobanteId: { type: String, required: true } });
const emit = defineEmits(["close", "cambiado"]);

const { hasPermission } = useAuth();
const puedeCobrar = computed(() => hasPermission("pagos:registrar"));

const c = ref(null);
const cargando = ref(true);

async function cargar() {
  cargando.value = true;
  try {
    const r = await facturacionApi.obtener(props.comprobanteId);
    c.value = r.data;
  } finally {
    cargando.value = false;
  }
}

function imprimir() { window.print(); }

async function cobrar() {
  const monto = await notify.prompt("Registrar cobro", {
    text: `Saldo pendiente: ${fmtSoles(c.value.saldo_pendiente)}`,
    inputType: "number",
    defaultValue: String(c.value.saldo_pendiente),
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
      cliente_id: c.value.cliente.id,
      monto: Number(monto),
      metodo,
      aplicaciones: [{ comprobante_id: c.value.id, monto: Number(monto) }],
    });
    notify.success("Cobro registrado");
    await cargar();
    emit("cambiado");
  } catch (e) {
    notify.error("No se pudo registrar el cobro", e.message);
  }
}

onMounted(cargar);
</script>

<style scoped>
.doc-head { display: flex; justify-content: space-between; gap: 20px; align-items: flex-start; }
.emisor { font-size: 15px; font-weight: 700; color: var(--ink); }
.totales { margin-top: 14px; margin-left: auto; width: 280px; display: flex; flex-direction: column; gap: 6px; }
.totales > div { display: flex; justify-content: space-between; font-size: 13px; color: var(--ink-2); }
.totales .total { border-top: 1px solid var(--line); padding-top: 8px; font-size: 16px; font-weight: 700; color: var(--ink); }
.totales .saldo { color: var(--red-ink); font-weight: 600; }
</style>
