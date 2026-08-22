<template>
  <div class="toggle-group">
    <button
      v-for="opt in options"
      :key="opt.value"
      :class="value === opt.value ? 'active' : ''"
      @click="$emit('change', opt.value)"
    >
      <component :is="opt.icon" v-if="opt.icon" :size="13" />
      {{ " " + opt.label }}
    </button>
  </div>
</template>

<script setup>
defineProps({
  options: { type: Array, required: true },
  value: { type: String, required: true }
});
defineEmits(["change"]);
</script>
