<template>
  <svg :width="width" :height="height" :viewBox="`0 0 ${width} ${height}`" aria-hidden="true">
    <line
      v-if="empty"
      :x1="2" :y1="height - 4" :x2="width - 2" :y2="height - 4"
      stroke="var(--ink-4)" stroke-width="1"
      stroke-dasharray="2 3" stroke-linecap="round"
    />
    <path
      v-else
      :d="path"
      fill="none"
      :stroke="stroke"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    />
  </svg>
</template>

<script setup>
import { computed } from "vue";

const props = defineProps({
  points: { type: Array, required: true },
  stroke: { type: String, default: "var(--emerald)" },
  width: { type: Number, default: 64 },
  height: { type: Number, default: 22 },
});

const empty = computed(() => !props.points?.length || props.points.every((v) => !v));

const path = computed(() => {
  const pts = props.points || [];
  if (!pts.length) return "";
  const pad = 2;
  const min = Math.min(...pts);
  const max = Math.max(...pts);
  const range = max - min || 1;
  const step = (props.width - pad * 2) / Math.max(pts.length - 1, 1);
  return pts.map((v, i) => {
    const x = pad + i * step;
    const y = props.height - pad - ((v - min) / range) * (props.height - pad * 2);
    return `${i === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`;
  }).join(" ");
});
</script>
