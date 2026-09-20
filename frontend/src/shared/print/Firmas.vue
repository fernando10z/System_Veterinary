<template>
  <div class="doc-firmas">
    <div v-for="(f, i) in visibles" :key="i" class="doc-firma">
      <div class="linea"></div>
      <div class="nombre">{{ f.nombre || "—" }}</div>
      <div class="detalle">
        <template v-if="f.colegiatura">M.V. · C.M.V.P. {{ f.colegiatura }}</template>
        <template v-else>{{ f.rol || "" }}</template>
      </div>
      <div v-if="f.especializacion" class="detalle">{{ f.especializacion }}</div>
    </div>
  </div>
</template>

<script setup>
import { computed } from "vue";

const props = defineProps({
  /** [{ nombre, colegiatura?, especializacion?, rol? }] */
  firmas: { type: Array, default: () => [] },
});

// Una firma sin nombre es un profesional que no se asignó (p. ej. la cirugía
// sin anestesista): no se imprime una línea vacía que nadie va a firmar.
const visibles = computed(() => props.firmas.filter((f) => f && (f.nombre || f.rol)));
</script>
