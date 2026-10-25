<template>
  <!-- Paso 1: comprobante con lo pendiente del cliente -->
  <EmitirComprobanteModal
    v-if="!comprobante"
    :cliente="cliente"
    :mascota="mascota"
    :mascota-id="mascotaId"
    :consulta-id="consultaId"
    :cita-id="citaId"
    @close="$emit('close')"
    @emitido="onEmitido"
  />
  <!-- Paso 2: cobro inmediato del comprobante recién emitido -->
  <CobroModal
    v-else
    :comprobante="comprobante"
    @close="terminar(false)"
    @cobrado="terminar(true)"
  />
</template>

<script setup>
import { ref } from "vue";
import EmitirComprobanteModal from "./EmitirComprobanteModal.vue";
import CobroModal from "../../pagos/components/CobroModal.vue";
import { fmtSoles } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

/**
 * Atención → boleta → cobro sin pasar por Facturación. Se abre desde la
 * consulta, la cita atendida o la sala de espera con el cliente ya elegido.
 */
defineProps({
  cliente: { type: Object, default: null },
  mascota: { type: String, default: "" },
  mascotaId: { type: String, default: "" },
  consultaId: { type: String, default: "" },
  citaId: { type: String, default: "" },
});
const emit = defineEmits(["close", "listo"]);

const comprobante = ref(null);
const emitido = ref(null);

function onEmitido(data, { cobrar } = {}) {
  emitido.value = data;
  if (cobrar && Number(data.saldo_pendiente) > 0) {
    comprobante.value = data;
    return;
  }
  notify.success("Comprobante emitido", `${data.numero_completo} · ${fmtSoles(data.total)}`);
  emit("listo", { comprobante: data, cobrado: false });
}

function terminar(cobrado) {
  if (!cobrado) {
    notify.info(
      "Comprobante emitido sin cobrar",
      `${emitido.value.numero_completo} quedó pendiente en Cobranzas.`,
    );
  }
  emit("listo", { comprobante: emitido.value, cobrado });
}
</script>
