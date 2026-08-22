<template>
  <div v-if="open" class="modal-back" @click="$emit('close')">
    <div :class="['modal', `modal-${size}`]" @click.stop>
      <div v-if="title || $slots.header" class="m-head">
        <slot name="header"><h3>{{ title }}</h3></slot>
      </div>
      <div class="m-body"><slot /></div>
      <div v-if="$slots.footerActions" class="m-foot"><slot name="footerActions" /></div>
    </div>
  </div>
</template>

<script setup>
import { onUnmounted, watch } from "vue";

const props = defineProps({
  open: { type: Boolean, required: true },
  title: { type: String, default: null },
  size: { type: String, default: "default", validator: (v) => ["default", "wide", "xwide", "doc"].includes(v) },
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

<style scoped>
.modal-wide { width: 640px !important; max-width: calc(100vw - 32px); }
.modal-xwide { width: 820px !important; max-width: calc(100vw - 32px); }
/* "doc": modales que muestran un documento a tamaño legible (comprobantes,
   proformas). Necesitan más ancho que xwide o el papel sale apretado. */
.modal-doc { width: 1180px !important; max-width: calc(100vw - 32px); }
</style>
