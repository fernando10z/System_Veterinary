<template>
  <div :style="{ display: 'flex', alignItems: 'center', gap: '8px', minWidth: '120px' }">
    <div class="progress-bar" :style="{ flex: 1, height: height + 'px' }">
      <div class="fill" :style="{ width: clamped + '%', background: color }" />
    </div>
    <span
      v-if="showLabel"
      :style="{ fontFamily: 'var(--font-mono)', fontSize: '11.5px', color: 'var(--ink-2)', minWidth: '32px', textAlign: 'right' }"
    >{{ clamped }}%</span>
  </div>
</template>

<script setup>
import { computed } from "vue";

const props = defineProps({
  value: { type: Number, default: 0 },
  color: { type: String, default: "var(--green)" },
  height: { type: Number, default: 6 },
  showLabel: { type: Boolean, default: false }
});

const clamped = computed(() => Math.max(0, Math.min(100, props.value)));
</script>
