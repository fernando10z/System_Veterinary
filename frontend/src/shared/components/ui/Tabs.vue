<template>
  <div class="tabs">
    <button
      v-for="t in tabs"
      :key="t.key"
      :class="['tab', active === t.key ? 'active' : '']"
      @click="$emit('change', t.key)"
    >
      {{ t.label }}
      <span v-if="t.count != null" class="count">{{ t.count }}</span>
    </button>
  </div>
</template>

<script setup>
defineProps({
  tabs: { type: Array, required: true },
  active: { type: String, required: true }
});
defineEmits(["change"]);
</script>
