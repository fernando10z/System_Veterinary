<template>
  <div class="doc-viewport">
    <!-- Barra de acciones: nunca se imprime -->
    <div class="doc-toolbar no-imprimir">
      <button class="btn" @click="volver"><ArrowLeft :size="14" /> Volver</button>
      <button class="btn primary" :disabled="cargando || !!error" @click="imprimir">
        <Printer :size="14" /> Imprimir
      </button>
      <slot name="acciones" />
      <span class="sep"></span>
      <span v-if="aviso" class="aviso">{{ aviso }}</span>
    </div>

    <div v-if="cargando" class="hoja">
      <p class="muted">Preparando el documento…</p>
    </div>

    <div v-else-if="error" class="hoja">
      <div class="doc-aviso grave"><strong>No se pudo generar el documento.</strong> {{ error }}</div>
    </div>

    <slot v-else />
  </div>
</template>

<script setup>
import { onMounted } from "vue";
import { useRouter } from "vue-router";
import { ArrowLeft, Printer } from "lucide-vue-next";

const props = defineProps({
  cargando: { type: Boolean, default: false },
  error: { type: String, default: "" },
  /** Advertencia en la barra: algo que conviene ver antes de imprimir. */
  aviso: { type: String, default: "" },
  /**
   * Abre el diálogo de impresión apenas el documento está listo. Se usa cuando
   * se llega con ?auto=1 desde un botón "Imprimir" de otra pantalla: el
   * recorrido natural del mostrador es un clic, no dos.
   */
  auto: { type: Boolean, default: false },
});

const router = useRouter();

function volver() {
  // Si la vista se abrió en pestaña nueva no hay historial al que volver.
  if (window.history.length > 1) router.back();
  else window.close();
}

function imprimir() {
  window.print();
}

onMounted(() => {
  if (!props.auto) return;
  // Se espera al siguiente frame para que el navegador haya pintado la hoja:
  // imprimir antes deja el diálogo con la página a medio renderizar.
  requestAnimationFrame(() => setTimeout(imprimir, 350));
});

defineExpose({ imprimir });
</script>
