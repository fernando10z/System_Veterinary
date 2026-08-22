<template>
  <div v-if="total > 0" class="pgn">
    <div class="pgn-info">
      Mostrando <strong>{{ desde }}</strong>–<template v-if="editablePageSize">
        <input
          v-if="editando"
          ref="inputRef"
          v-model="borrador"
          class="pgn-size-input"
          type="number"
          min="1"
          :max="total"
          @keydown.enter="confirmar"
          @keydown.esc="editando = false"
          @blur="confirmar"
        />
        <button
          v-else
          class="pgn-size-btn"
          title="Cambiar cuántos ver por página"
          @click="abrirEditor"
        >
          {{ hasta }}
        </button>
      </template>
      <strong v-else>{{ hasta }}</strong>
      de <strong>{{ total }}</strong>
    </div>

    <nav v-if="totalPages > 1" class="pgn-controls" aria-label="Paginación">
      <button
        class="pgn-btn pgn-arrow"
        :disabled="page <= 1"
        title="Anterior"
        @click="go(page - 1)"
      >
        <ChevronLeft :size="14" />
      </button>

      <template v-for="(p, i) in pages" :key="i">
        <span v-if="p === '…'" class="pgn-dots">…</span>
        <button
          v-else
          :class="['pgn-btn pgn-num', p === page ? 'pgn-active' : '']"
          @click="go(p)"
        >
          {{ p }}
        </button>
      </template>

      <button
        class="pgn-btn pgn-arrow"
        :disabled="page >= totalPages"
        title="Siguiente"
        @click="go(page + 1)"
      >
        <ChevronRight :size="14" />
      </button>
    </nav>
  </div>
</template>

<script setup>
import { computed, nextTick, ref } from "vue";
import { ChevronLeft, ChevronRight } from "lucide-vue-next";

const props = defineProps({
  page: { type: Number, required: true },
  total: { type: Number, required: true },
  pageSize: { type: Number, default: 10 },
  /** cuántos números mostrar alrededor de la página actual */
  siblingCount: { type: Number, default: 1 },
  /** permite editar el tamaño de página haciendo click sobre el número */
  editablePageSize: { type: Boolean, default: false },
});
const emit = defineEmits(["change", "update:pageSize"]);

const totalPages = computed(() =>
  Math.max(1, Math.ceil(props.total / Math.max(props.pageSize, 1))),
);

const desde = computed(() =>
  props.total === 0 ? 0 : (props.page - 1) * props.pageSize + 1,
);
const hasta = computed(() =>
  Math.min(props.page * props.pageSize, props.total),
);

/**
 * Genera el array de números a renderizar, con elipsis donde corresponda.
 * Ejemplo (page=5, total=12): [1, '…', 4, 5, 6, '…', 12]
 */
const pages = computed(() => {
  const tp = totalPages.value;
  const s = props.siblingCount;
  const range = [];

  if (tp <= 7 + s * 2) {
    for (let i = 1; i <= tp; i++) range.push(i);
    return range;
  }

  const left = Math.max(props.page - s, 2);
  const right = Math.min(props.page + s, tp - 1);
  const showLeftDots = left > 2;
  const showRightDots = right < tp - 1;

  range.push(1);
  if (showLeftDots) range.push("…");
  for (let i = left; i <= right; i++) range.push(i);
  if (showRightDots) range.push("…");
  range.push(tp);
  return range;
});

function go(p) {
  if (p < 1 || p > totalPages.value || p === props.page) return;
  emit("change", p);
}

const editando = ref(false);
const borrador = ref("");
const inputRef = ref(null);

async function abrirEditor() {
  borrador.value = String(props.pageSize);
  editando.value = true;
  await nextTick();
  inputRef.value?.select();
}

function confirmar() {
  if (!editando.value) return;
  editando.value = false;
  const n = Math.trunc(Number(borrador.value));
  if (!Number.isFinite(n) || n < 1) return;
  const size = Math.min(n, props.total);
  if (size === props.pageSize) return;
  emit("update:pageSize", size);
  // El nuevo tamaño puede dejar la página actual fuera de rango: volvemos al inicio.
  if (props.page !== 1) emit("change", 1);
}
</script>

<style scoped>
.pgn {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  width: 100%;
}
.pgn-info {
  font-size: 12.5px;
  color: var(--ink-3);
}
.pgn-info strong {
  color: var(--ink);
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.pgn-size-btn {
  padding: 0 3px;
  background: transparent;
  border: none;
  border-bottom: 1px dashed var(--line-strong);
  border-radius: 3px;
  font: inherit;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  color: var(--ink);
  cursor: pointer;
  transition: background 0.12s, color 0.12s;
}
.pgn-size-btn:hover {
  background: var(--bg-soft);
  color: var(--emerald);
  border-bottom-color: var(--emerald);
}
.pgn-size-input {
  width: 52px;
  height: 22px;
  padding: 0 4px;
  background: var(--bg-elev);
  border: 1px solid var(--emerald);
  border-radius: 5px;
  font: inherit;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  color: var(--ink);
  outline: none;
}

.pgn-controls {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.pgn-btn {
  min-width: 30px;
  height: 30px;
  padding: 0 8px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: var(--bg-elev);
  border: 1px solid var(--line);
  border-radius: 7px;
  font-size: 12.5px;
  font-weight: 500;
  font-variant-numeric: tabular-nums;
  color: var(--ink-2);
  cursor: pointer;
  transition: background 0.12s, border-color 0.12s, color 0.12s, transform 0.08s;
}
.pgn-btn:hover:not(:disabled) {
  background: var(--bg-soft);
  border-color: var(--line-strong);
  color: var(--ink);
}
.pgn-btn:active:not(:disabled) {
  transform: translateY(1px);
}
.pgn-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.pgn-active {
  background: var(--emerald);
  border-color: var(--emerald);
  color: white;
  box-shadow: 0 1px 0 rgba(255,255,255,0.2) inset, 0 1px 2px rgba(7,177,98,0.25);
}
.pgn-active:hover:not(:disabled) {
  background: var(--emerald-deep);
  border-color: var(--emerald-deep);
  color: white;
}

.pgn-arrow svg { color: inherit; }

.pgn-dots {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 22px;
  color: var(--ink-4);
  font-weight: 600;
  user-select: none;
}
</style>
