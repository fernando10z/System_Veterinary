<template>
  <span :class="['status-pill', variant]" :style="styleProp">
    <span v-if="withDot" class="dot" />
    <slot />
  </span>
</template>

<script setup>
defineProps({
  variant: { type: String, default: "neutral" },
  withDot: { type: Boolean, default: true },
  styleProp: { type: Object, default: () => ({}) }
});
</script>
