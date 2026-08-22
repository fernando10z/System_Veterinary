<template>
  <div
    ref="rootRef"
    :class="['sm', flavor === 'fil' ? 'sm-fil' : 'sm-input', { 'sm--open': open, 'sm--disabled': disabled }]"
  >
    <button
      type="button"
      class="sm-trigger"
      :disabled="disabled"
      :aria-expanded="open"
      :aria-haspopup="'listbox'"
      @click="toggle"
      @keydown.down.prevent="onArrowDown"
      @keydown.up.prevent="onArrowUp"
      @keydown.enter.prevent="onEnter"
      @keydown.esc.prevent="close"
    >
      <slot name="leading"></slot>
      <span :class="['sm-label', selectedOption ? '' : 'sm-label-empty']">
        {{ selectedOption?.label || placeholder }}
      </span>
      <ChevronDown :size="14" :class="['sm-chev', open ? 'sm-chev-open' : '']" />
    </button>

    <Transition name="sm-pop">
      <div v-if="open" class="sm-menu" role="listbox">
        <button
          v-for="(o, i) in options"
          :key="o.value"
          type="button"
          role="option"
          :aria-selected="o.value === modelValue"
          :class="[
            'sm-item',
            i === highlight ? 'sm-item-active' : '',
            o.value === modelValue ? 'sm-item-selected' : '',
          ]"
          @click="select(o)"
          @mouseenter="highlight = i"
        >
          <span class="sm-item-label">
            <span v-if="o.dot" class="sm-item-dot" :style="{ background: o.dot }"></span>
            {{ o.label }}
            <small v-if="o.hint" class="sm-item-hint">{{ o.hint }}</small>
          </span>
          <Check v-if="o.value === modelValue" :size="13" class="sm-check" />
        </button>

        <div v-if="!options.length" class="sm-empty">Sin opciones</div>
      </div>
    </Transition>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount, watch, nextTick } from "vue";
import { ChevronDown, Check } from "lucide-vue-next";

const props = defineProps({
  modelValue: { type: [String, Number, Boolean, null], default: null },
  options: { type: Array, required: true },
  placeholder: { type: String, default: "Seleccionar…" },
  disabled: { type: Boolean, default: false },
  /** "fil" = estilo del filter row · "input" = estilo de form input (modales) */
  flavor: { type: String, default: "input", validator: (v) => ["fil", "input"].includes(v) },
});
const emit = defineEmits(["update:modelValue", "change"]);

const rootRef = ref(null);
const open = ref(false);
const highlight = ref(0);

const selectedOption = computed(() =>
  props.options.find((o) => o.value === props.modelValue) || null,
);

watch(() => props.modelValue, () => {
  const idx = props.options.findIndex((o) => o.value === props.modelValue);
  if (idx >= 0) highlight.value = idx;
});

function toggle() {
  if (props.disabled) return;
  open.value ? close() : openMenu();
}
function openMenu() {
  open.value = true;
  const idx = props.options.findIndex((o) => o.value === props.modelValue);
  highlight.value = idx >= 0 ? idx : 0;
  nextTick(() => {
    document.addEventListener("mousedown", onDocClick);
  });
}
function close() {
  open.value = false;
  document.removeEventListener("mousedown", onDocClick);
}
function onDocClick(e) {
  if (rootRef.value && !rootRef.value.contains(e.target)) close();
}

function onArrowDown() {
  if (!open.value) return openMenu();
  if (!props.options.length) return;
  highlight.value = (highlight.value + 1) % props.options.length;
}
function onArrowUp() {
  if (!open.value) return openMenu();
  if (!props.options.length) return;
  highlight.value = (highlight.value - 1 + props.options.length) % props.options.length;
}
function onEnter() {
  if (!open.value) return openMenu();
  const o = props.options[highlight.value];
  if (o) select(o);
}

function select(o) {
  emit("update:modelValue", o.value);
  emit("change", o.value);
  close();
}

onMounted(() => {
  const idx = props.options.findIndex((o) => o.value === props.modelValue);
  if (idx >= 0) highlight.value = idx;
});
onBeforeUnmount(() => {
  document.removeEventListener("mousedown", onDocClick);
});
</script>

<style scoped>
.sm { position: relative; min-width: 0; }

/* ── Trigger: variante "fil" (filter row, transparente, icono leading externo) ── */
.sm-fil .sm-trigger {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  width: 100%;
  min-width: 160px;
  padding: 6px 11px;
  background: var(--bg);
  border: 1px solid var(--line);
  border-radius: 7px;
  font-size: 13px;
  color: var(--ink);
  cursor: pointer;
  font-family: inherit;
  transition: border-color 0.12s, box-shadow 0.12s, background 0.12s;
}
.sm-fil .sm-trigger:hover { border-color: var(--line-strong); }
.sm-fil.sm--open .sm-trigger {
  border-color: var(--emerald);
  background: var(--bg-elev);
  box-shadow: 0 0 0 3px var(--emerald-soft);
}

/* ── Trigger: variante "input" (modales / form fields) ── */
.sm-input .sm-trigger {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  width: 100%;
  padding: 8px 11px;
  background: var(--bg-elev);
  border: 1px solid var(--line);
  border-radius: 8px;
  font-size: 13px;
  color: var(--ink);
  cursor: pointer;
  font-family: inherit;
  transition: border-color 0.12s, box-shadow 0.12s;
}
.sm-input .sm-trigger:hover { border-color: var(--line-strong); }
.sm-input.sm--open .sm-trigger {
  border-color: var(--emerald);
  box-shadow: 0 0 0 3px var(--emerald-soft);
}

.sm--disabled .sm-trigger {
  background: var(--bg-soft);
  color: var(--ink-3);
  cursor: not-allowed;
}

.sm-label { flex: 1; text-align: left; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sm-label-empty { color: var(--ink-4); }
.sm-chev {
  flex-shrink: 0; color: var(--ink-3);
  transition: transform 0.18s ease, color 0.12s;
}
.sm-chev-open { transform: rotate(180deg); color: var(--emerald-deep); }

/* leading slot icon (svg) styling */
.sm-trigger :slotted(svg) {
  flex-shrink: 0;
  color: var(--ink-4);
}
.sm--open .sm-trigger :slotted(svg) { color: var(--emerald-deep); }

/* ── Menu ── */
.sm-menu {
  position: absolute;
  top: calc(100% + 6px);
  left: 0;
  right: 0;
  min-width: 100%;
  background: var(--bg-elev);
  border: 1px solid var(--line);
  border-radius: 10px;
  box-shadow: var(--shadow-lg);
  padding: 5px;
  z-index: 50;
  max-height: 280px;
  overflow-y: auto;
  /* glow esmeralda sutil */
  outline: 1px solid var(--emerald-line);
  outline-offset: -1px;
}

.sm-pop-enter-active, .sm-pop-leave-active {
  transition: opacity 0.14s ease, transform 0.14s ease;
}
.sm-pop-enter-from, .sm-pop-leave-to {
  opacity: 0;
  transform: translateY(-4px) scale(0.98);
}

.sm-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  width: 100%;
  padding: 8px 11px;
  border: 0;
  background: transparent;
  border-radius: 7px;
  font-size: 13px;
  color: var(--ink);
  text-align: left;
  cursor: pointer;
  font-family: inherit;
  transition: background 0.08s, color 0.08s;
}
.sm-item:hover, .sm-item-active {
  background: var(--emerald-soft);
  color: var(--emerald-ink);
}
.sm-item-selected {
  background: var(--bg-soft);
  color: var(--ink);
  font-weight: 500;
}
.sm-item-selected.sm-item-active {
  background: var(--emerald-soft);
  color: var(--emerald-ink);
}

.sm-item-label {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}
.sm-item-dot {
  width: 8px; height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
}
.sm-item-hint {
  color: var(--ink-3);
  font-size: 11px;
  margin-left: 4px;
}
.sm-item-selected .sm-item-hint { color: var(--ink-2); }
.sm-item-active .sm-item-hint { color: var(--emerald-deep); }

.sm-check {
  color: var(--emerald-deep);
  flex-shrink: 0;
}
.sm-item-active .sm-check { color: var(--emerald-darker, var(--emerald-deep)); }

.sm-empty {
  padding: 16px 11px;
  text-align: center;
  font-size: 12.5px;
  color: var(--ink-3);
}
</style>
