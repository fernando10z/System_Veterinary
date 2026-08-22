<template>
  <div class="pipeline">
    <span
      v-for="(s, i) in steps"
      :key="s.value"
      :style="{ display: 'inline-flex', alignItems: 'center' }"
    >
      <span :class="stepClass(i)">
        <Check v-if="i < idx" class="check" :size="10" />
        {{ s.label }}
      </span>
      <span v-if="i < steps.length - 1" class="sep" />
    </span>
  </div>
</template>

<script setup>
import { computed } from "vue";
import { Check } from "lucide-vue-next";

const props = defineProps({
  steps: { type: Array, required: true },
  current: { type: String, required: true }
});

const idx = computed(() => props.steps.findIndex((s) => s.value === props.current));

function stepClass(i) {
  let cls = "step";
  if (i < idx.value) cls += " done";
  else if (i === idx.value) cls += " current";
  return cls;
}
</script>
