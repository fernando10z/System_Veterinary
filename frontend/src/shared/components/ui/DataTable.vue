<template>
  <div class="tbl-shell">
    <div class="tbl-scroll">
      <table class="stbl">
        <thead>
          <tr>
            <th
              v-for="c in columns"
              :key="c.key"
              :style="c.align ? { textAlign: c.align } : undefined"
            >
              <div class="th-inner">{{ c.label }}</div>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="data.length === 0">
            <td
              :colspan="columns.length"
              :style="{ textAlign: 'center', padding: '36px', color: 'var(--ink-3)' }"
            >{{ emptyState || "Sin resultados" }}</td>
          </tr>
          <tr
            v-for="row in data"
            :key="row[rowKey]"
            :style="{ cursor: hasRowClick ? 'pointer' : 'default' }"
            @click="hasRowClick && $emit('row-click', row)"
          >
            <td
              v-for="c in columns"
              :key="c.key"
              :style="c.align ? { textAlign: c.align } : undefined"
            >
              <slot :name="'cell-' + c.key" :row="row">
                {{ c.render ? c.render(row) : row[c.key] }}
              </slot>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup>
import { computed, useSlots } from "vue";

const props = defineProps({
  columns: { type: Array, required: true },
  data: { type: Array, required: true },
  emptyState: { type: String, default: null },
  rowKey: { type: String, default: "id" }
});
const emit = defineEmits(["row-click"]);
const slots = useSlots();
const hasRowClick = computed(() => true);
</script>
