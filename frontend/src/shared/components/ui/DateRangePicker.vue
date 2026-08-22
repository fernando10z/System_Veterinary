<template>
  <div ref="root" class="drp">
    <button ref="trigger" type="button" class="drp-trigger" :class="{ open }" @click="toggle">
      <CalendarClock :size="14" />
      <span v-if="desde || hasta" class="drp-val">{{ label }}</span>
      <span v-else class="drp-ph">Seleccionar fechas</span>
      <ChevronDown :size="14" class="drp-caret" />
    </button>

    <Teleport to="body">
    <div v-if="open" ref="pop" class="drp-pop" :style="popStyle">
      <!-- Atajos rápidos (pensados para conteo mensual) -->
      <div class="drp-presets">
        <button
          v-for="p in presets"
          :key="p.key"
          type="button"
          class="preset"
          :class="{ active: activePreset === p.key }"
          @click="aplicarPreset(p)"
        >{{ p.label }}</button>
      </div>

      <!-- Calendario -->
      <div class="drp-cal">
        <div class="cal-head">
          <button type="button" class="cal-nav" @click="mover(-1)"><ChevronLeft :size="16" /></button>
          <span class="cal-title">{{ tituloMes }}</span>
          <button type="button" class="cal-nav" @click="mover(1)"><ChevronRight :size="16" /></button>
        </div>

        <div class="cal-grid">
          <span v-for="d in DOW" :key="d" class="dow">{{ d }}</span>
          <template v-for="(cell, i) in celdas" :key="i">
            <span v-if="!cell" class="day empty"></span>
            <button
              v-else
              type="button"
              class="day"
              :class="{
                start: cell.iso === sel.desde,
                end: cell.iso === sel.hasta,
                range: enRango(cell.iso),
                today: cell.iso === hoyIso,
              }"
              @click="elegirDia(cell.iso)"
            >{{ cell.dia }}</button>
          </template>
        </div>

        <div class="cal-foot">
          <span class="cal-sel">{{ selLabel }}</span>
          <div class="cal-actions">
            <button type="button" class="btn-clear" @click="limpiar">Limpiar</button>
            <button type="button" class="btn-apply" :disabled="!sel.desde" @click="aplicar">Aplicar</button>
          </div>
        </div>
      </div>
    </div>
    </Teleport>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted, onBeforeUnmount } from "vue";
import { CalendarClock, ChevronDown, ChevronLeft, ChevronRight } from "lucide-vue-next";

const props = defineProps({
  desde: { type: String, default: "" },
  hasta: { type: String, default: "" },
});
const emit = defineEmits(["update:desde", "update:hasta", "apply"]);

const DOW = ["L", "M", "X", "J", "V", "S", "D"];

// --- Helpers de fecha local (YYYY-MM-DD sin corrimiento por UTC) ---
function iso(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function parse(s) {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(y, m - 1, d);
}
const hoy = new Date();
const hoyIso = iso(hoy);

const open = ref(false);
const root = ref(null);
const trigger = ref(null);
const pop = ref(null);
// Posición fija del popover (teleport a body para que ningún panel con
// overflow:hidden lo recorte). Se alinea a la DERECHA del botón, abriéndose
// hacia la izquierda, y se sujeta a los bordes de la ventana.
const popStyle = ref({});
function posicionar() {
  const el = trigger.value;
  if (!el) return;
  const r = el.getBoundingClientRect();
  const margen = 8;
  const anchoPop = 384; // presets (130) + calendario (252) + bordes
  // Alineado a la derecha del botón; si no cabe hacia la izquierda, se pega al borde.
  let left = r.right - anchoPop;
  if (left < margen) left = margen;
  const maxLeft = window.innerWidth - anchoPop - margen;
  if (left > maxLeft) left = Math.max(margen, maxLeft);
  popStyle.value = {
    position: "fixed",
    top: `${r.bottom + 6}px`,
    left: `${left}px`,
  };
}

// Selección en curso (se confirma con Aplicar).
const sel = reactive({ desde: props.desde || "", hasta: props.hasta || "" });
// Mes visible en el calendario.
const vista = ref(new Date(hoy.getFullYear(), hoy.getMonth(), 1));

watch(() => [props.desde, props.hasta], ([d, h]) => {
  sel.desde = d || "";
  sel.hasta = h || "";
});

const tituloMes = computed(() =>
  vista.value.toLocaleDateString("es-PE", { month: "long", year: "numeric" }),
);

const celdas = computed(() => {
  const y = vista.value.getFullYear();
  const m = vista.value.getMonth();
  const primero = new Date(y, m, 1);
  const offset = (primero.getDay() + 6) % 7; // lunes primero
  const dias = new Date(y, m + 1, 0).getDate();
  const out = [];
  for (let i = 0; i < offset; i++) out.push(null);
  for (let d = 1; d <= dias; d++) out.push({ dia: d, iso: iso(new Date(y, m, d)) });
  return out;
});

function enRango(v) {
  if (!sel.desde || !sel.hasta) return false;
  return v > sel.desde && v < sel.hasta;
}

function elegirDia(v) {
  // Sin inicio, o rango ya completo → empieza uno nuevo.
  if (!sel.desde || (sel.desde && sel.hasta)) {
    sel.desde = v;
    sel.hasta = "";
    return;
  }
  // Con inicio y sin fin: si es anterior, reinicia; si no, cierra el rango.
  if (v < sel.desde) sel.desde = v;
  else sel.hasta = v;
}

function mover(n) {
  vista.value = new Date(vista.value.getFullYear(), vista.value.getMonth() + n, 1);
}

// --- Atajos ---
const presets = [
  { key: "hoy", label: "Hoy" },
  { key: "mes", label: "Este mes" },
  { key: "mesPasado", label: "Mes pasado" },
  { key: "30", label: "Últimos 30 días" },
  { key: "anio", label: "Este año" },
];
function rangoPreset(key) {
  const y = hoy.getFullYear();
  const m = hoy.getMonth();
  if (key === "hoy") return [hoyIso, hoyIso];
  if (key === "mes") return [iso(new Date(y, m, 1)), iso(new Date(y, m + 1, 0))];
  if (key === "mesPasado") return [iso(new Date(y, m - 1, 1)), iso(new Date(y, m, 0))];
  if (key === "30") { const d = new Date(hoy); d.setDate(d.getDate() - 29); return [iso(d), hoyIso]; }
  if (key === "anio") return [iso(new Date(y, 0, 1)), iso(new Date(y, 11, 31))];
  return ["", ""];
}
const activePreset = computed(() => {
  for (const p of presets) {
    const [d, h] = rangoPreset(p.key);
    if (d === sel.desde && h === sel.hasta) return p.key;
  }
  return null;
});
function aplicarPreset(p) {
  const [d, h] = rangoPreset(p.key);
  sel.desde = d;
  sel.hasta = h;
  vista.value = parse(d);
  vista.value = new Date(vista.value.getFullYear(), vista.value.getMonth(), 1);
  aplicar();
}

// --- Confirmar / limpiar ---
function fmt(s) {
  return s ? parse(s).toLocaleDateString("es-PE", { day: "2-digit", month: "short", year: "numeric" }) : "";
}
const label = computed(() => {
  if (props.desde && props.hasta) return `${fmt(props.desde)} – ${fmt(props.hasta)}`;
  if (props.desde) return `Desde ${fmt(props.desde)}`;
  if (props.hasta) return `Hasta ${fmt(props.hasta)}`;
  return "";
});
const selLabel = computed(() => {
  if (sel.desde && sel.hasta) return `${fmt(sel.desde)} – ${fmt(sel.hasta)}`;
  if (sel.desde) return "Elige la fecha final…";
  return "Elige la fecha inicial";
});

function aplicar() {
  // Si solo eligió una fecha, se usa como día único (desde = hasta).
  const d = sel.desde;
  const h = sel.hasta || sel.desde;
  sel.hasta = h;
  emit("update:desde", d || "");
  emit("update:hasta", h || "");
  emit("apply");
  open.value = false;
}
function limpiar() {
  sel.desde = "";
  sel.hasta = "";
  emit("update:desde", "");
  emit("update:hasta", "");
  emit("apply");
  open.value = false;
}

function toggle() {
  open.value = !open.value;
  if (open.value) {
    if (sel.desde) vista.value = new Date(parse(sel.desde).getFullYear(), parse(sel.desde).getMonth(), 1);
    posicionar();
  }
}
function onDocClick(e) {
  if (!open.value) return;
  if (root.value && root.value.contains(e.target)) return;
  if (pop.value && pop.value.contains(e.target)) return;
  open.value = false;
}
function onReflow() {
  if (open.value) posicionar();
}
onMounted(() => {
  document.addEventListener("mousedown", onDocClick);
  window.addEventListener("resize", onReflow);
  window.addEventListener("scroll", onReflow, true); // capture: sigue scrolls internos
});
onBeforeUnmount(() => {
  document.removeEventListener("mousedown", onDocClick);
  window.removeEventListener("resize", onReflow);
  window.removeEventListener("scroll", onReflow, true);
});
</script>

<style scoped>
.drp { position: relative; display: inline-block; }

.drp-trigger {
  display: inline-flex; align-items: center; gap: 7px;
  padding: 6px 11px; background: var(--bg); border: 1px solid var(--line);
  border-radius: 7px; font-size: 12.5px; color: var(--ink); cursor: pointer;
  transition: border-color 0.12s, box-shadow 0.12s;
}
.drp-trigger:hover { border-color: var(--ink-3); }
.drp-trigger.open { border-color: var(--emerald); box-shadow: 0 0 0 3px var(--emerald-soft); }
.drp-trigger svg { color: var(--ink-4); flex-shrink: 0; }
.drp-trigger.open .drp-caret { transform: rotate(180deg); }
.drp-caret { transition: transform 0.12s; }
.drp-ph { color: var(--ink-4); }
.drp-val { font-weight: 500; }

.drp-pop {
  position: fixed; z-index: 100;
  display: flex;
  background: var(--bg-elev); border: 1px solid var(--line);
  border-radius: 12px; box-shadow: var(--shadow-lg); overflow: hidden;
}

.drp-presets {
  display: flex; flex-direction: column; gap: 2px;
  padding: 10px; border-right: 1px solid var(--line); background: var(--bg-soft);
  min-width: 130px;
}
.preset {
  text-align: left; border: 0; background: transparent; cursor: pointer;
  padding: 7px 10px; border-radius: 6px; font-size: 12.5px; color: var(--ink-2);
  white-space: nowrap; transition: background 0.1s, color 0.1s;
}
.preset:hover { background: var(--bg-elev); color: var(--ink); }
.preset.active { background: var(--emerald-soft); color: var(--emerald-deep); font-weight: 600; }

.drp-cal { padding: 12px; width: 252px; }
.cal-head {
  display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;
}
.cal-title { font-size: 13px; font-weight: 600; color: var(--ink); text-transform: capitalize; }
.cal-nav {
  display: inline-flex; align-items: center; justify-content: center;
  width: 26px; height: 26px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--bg-elev); color: var(--ink-3); cursor: pointer;
}
.cal-nav:hover { border-color: var(--ink-3); color: var(--ink); }

.cal-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 2px; }
.dow {
  text-align: center; font-size: 10.5px; font-weight: 600; color: var(--ink-4);
  padding-bottom: 4px; text-transform: uppercase;
}
.day {
  display: inline-flex; align-items: center; justify-content: center;
  height: 30px; border: 0; background: transparent; cursor: pointer;
  font-size: 12.5px; color: var(--ink-2); border-radius: 6px;
  transition: background 0.1s, color 0.1s;
}
.day.empty { pointer-events: none; }
.day:hover:not(.empty) { background: var(--bg-soft); }
.day.today { font-weight: 700; color: var(--emerald-deep); }
.day.range { background: var(--emerald-soft); border-radius: 0; color: var(--emerald-ink); }
.day.start, .day.end {
  background: var(--emerald); color: #fff; font-weight: 600;
}
.day.start { border-radius: 6px 0 0 6px; }
.day.end { border-radius: 0 6px 6px 0; }
.day.start.end { border-radius: 6px; }

.cal-foot {
  display: flex; align-items: center; justify-content: space-between; gap: 8px;
  margin-top: 10px; padding-top: 10px; border-top: 1px solid var(--line);
}
.cal-sel { font-size: 11.5px; color: var(--ink-3); }
.cal-actions { display: inline-flex; gap: 6px; }
.btn-clear {
  border: 1px solid var(--line); background: var(--bg-elev); color: var(--ink-3);
  font-size: 12px; padding: 5px 10px; border-radius: 6px; cursor: pointer;
}
.btn-clear:hover { color: var(--ink); border-color: var(--ink-3); }
.btn-apply {
  border: 0; background: var(--emerald); color: #fff;
  font-size: 12px; font-weight: 600; padding: 5px 12px; border-radius: 6px; cursor: pointer;
}
.btn-apply:disabled { opacity: 0.5; cursor: default; }

@media (max-width: 560px) {
  .drp-pop { flex-direction: column; }
  .drp-presets { flex-direction: row; flex-wrap: wrap; border-right: 0; border-bottom: 1px solid var(--line); min-width: 0; }
}
</style>
