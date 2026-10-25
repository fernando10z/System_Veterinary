<template>
  <div v-if="open" class="modal-back" v-dialogo="() => $emit('close')">
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
// Escape, clic en el fondo y confirmación de cambios los resuelve v-dialogo.
defineProps({
  open: { type: Boolean, required: true },
  title: { type: String, default: null },
  size: { type: String, default: "default", validator: (v) => ["default", "wide", "xwide", "doc"].includes(v) },
});
defineEmits(["close"]);
</script>
