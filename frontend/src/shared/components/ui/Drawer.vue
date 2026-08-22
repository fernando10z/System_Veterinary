<template>
  <template v-if="open">
    <div class="drawer-back" @click="$emit('close')" />
    <aside class="drawer" :style="{ width: width + 'px' }">
      <div class="d-head">
        <slot name="headerExtra" />
        <div class="who" :style="{ flex: 1 }">
          <h2 v-if="title">{{ title }}</h2>
          <div v-if="subtitle" class="meta">{{ subtitle }}</div>
        </div>
        <button class="row-action" aria-label="Cerrar" @click="$emit('close')">
          <X :size="16" />
        </button>
      </div>
      <div class="d-body"><slot /></div>
      <div v-if="$slots.footerActions" class="d-foot"><slot name="footerActions" /></div>
    </aside>
  </template>
</template>

<script setup>
import { onUnmounted, watch } from "vue";
import { X } from "lucide-vue-next";

const props = defineProps({
  open: { type: Boolean, required: true },
  title: { type: String, default: null },
  subtitle: { type: String, default: null },
  width: { type: Number, default: 460 }
});
const emit = defineEmits(["close"]);

function onKey(e) {
  if (e.key === "Escape") emit("close");
}

watch(() => props.open, (val) => {
  if (val) {
    window.addEventListener("keydown", onKey);
  } else {
    window.removeEventListener("keydown", onKey);
  }
}, { immediate: true });

onUnmounted(() => {
  window.removeEventListener("keydown", onKey);
});
</script>
