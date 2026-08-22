<template>
  <div class="dual-progress">
    <div class="dp-row">
      <span class="dp-label">F</span>
      <div class="dp-track"><div class="dp-fill fis" :style="{ width: f + '%' }" /></div>
      <span class="dp-pct">{{ f }}%</span>
    </div>
    <div class="dp-row">
      <span class="dp-label">$</span>
      <div class="dp-track"><div class="dp-fill fin" :style="{ width: fn + '%' }" /></div>
      <span class="dp-pct">{{ fn }}%</span>
    </div>
  </div>
</template>

<script setup>
import { computed } from "vue";

const props = defineProps({
  fisico: { type: Number, default: 0 },
  financiero: { type: Number, default: 0 }
});

const f = computed(() => Math.max(0, Math.min(100, props.fisico)));
const fn = computed(() => Math.max(0, Math.min(100, props.financiero)));
</script>
