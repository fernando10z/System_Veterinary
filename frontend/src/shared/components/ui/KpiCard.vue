<template>
  <div class="kpi" :style="{ '--bar': BAR_COLOR[barColor] || barColor }">
    <div class="k-label">
      <span>{{ label }}</span>
      <component :is="icon" v-if="icon" :size="14" class="k-icon" />
    </div>
    <div class="k-value">{{ value }}</div>
    <div class="k-foot">
      <span v-if="compareLabel">{{ compareLabel }}</span>
      <span v-if="delta" :class="['k-delta', delta.direction === 'up' ? 'up' : 'down']">
        <TrendingUp v-if="delta.direction === 'up'" :size="11" :style="{ verticalAlign: '-1px' }" />
        <TrendingDown v-else :size="11" :style="{ verticalAlign: '-1px' }" />
        {{ " " + delta.value }}
      </span>
    </div>
  </div>
</template>

<script setup>
import { TrendingUp, TrendingDown } from "lucide-vue-next";

const BAR_COLOR = {
  green: "#10B981",
  amber: "#F59E0B",
  blue: "#2563EB",
  violet: "#7C3AED",
  red: "#EF4444",
  neutral: "#A0A099"
};

defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  barColor: { type: String, default: "blue" },
  delta: { type: Object, default: null },
  compareLabel: { type: String, default: null },
  icon: { type: [Object, Function], default: null }
});
</script>
