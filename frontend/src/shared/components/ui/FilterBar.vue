<template>
  <div class="filter-bar">
    <button
      v-for="chip in normalizedChips"
      :key="chip.value"
      :class="['chip', activeChip === chip.value ? 'active' : '']"
      @click="$emit('chip-click', chip.value)"
    >
      <span v-if="activeChip === chip.value" class="dot" />
      {{ chip.label }}
      <span
        v-if="chip.count != null"
        :style="{ color: 'var(--ink-4)', fontSize: '11px' }"
      >{{ chip.count }}</span>
    </button>
    <span
      v-if="chips.length > 0"
      :style="{ width: '1px', height: '22px', background: 'var(--line)', margin: '0 4px' }"
    />
    <div v-if="searchPlaceholder !== undefined && searchPlaceholder !== null" class="input">
      <Search :size="14" color="var(--ink-4)" />
      <input
        :placeholder="searchPlaceholder"
        :value="search || ''"
        @input="$emit('search', $event.target.value)"
      />
    </div>
    <button v-if="showFilters" class="chip"><Filter :size="12" /> Filtros</button>
    <div class="spacer-h" />
    <slot name="extraActions" />
  </div>
</template>

<script setup>
import { computed } from "vue";
import { Search, Filter } from "lucide-vue-next";

const props = defineProps({
  chips: { type: Array, default: () => [] },
  activeChip: { type: [String, Number], default: null },
  searchPlaceholder: { type: String, default: undefined },
  search: { type: String, default: "" },
  showFilters: { type: Boolean, default: true }
});
defineEmits(["chip-click", "search"]);

const normalizedChips = computed(() => props.chips.map((chip) => {
  if (typeof chip === "string") return { value: chip, label: chip, count: undefined };
  return { value: chip.value, label: chip.label, count: chip.count };
}));
</script>
