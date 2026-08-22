<template>
  <div ref="rootRef" class="cmdk">
    <!-- La caja de búsqueda ES el input en vivo; el dropdown se despliega debajo. -->
    <div class="cmdk-box" :class="{ active: open }">
      <Search :size="14" color="var(--ink-4)" />
      <input
        ref="inputRef"
        v-model="query"
        class="cmdk-box-input"
        type="text"
        placeholder="Buscar módulos, propietarios o pacientes…"
        autocomplete="off"
        spellcheck="false"
        @focus="open = true"
        @keydown.down.prevent="move(1)"
        @keydown.up.prevent="move(-1)"
        @keydown.enter.prevent="chooseActive"
        @keydown.esc.prevent="closeAndBlur"
      />
      <kbd class="cmdk-kbd">{{ shortcut }}</kbd>
    </div>

    <Transition name="cmdk">
      <div v-if="open" ref="listRef" class="cmdk-dropdown" role="listbox" aria-label="Resultados de búsqueda">
        <template v-if="navResults.length">
          <div class="cmdk-group-label">Ir a</div>
          <button
            v-for="it in navResults"
            :key="'nav-' + it.to"
            :class="['cmdk-item', { active: flatIndex(it) === activeIndex }]"
            :data-idx="flatIndex(it)"
            @mousemove="activeIndex = flatIndex(it)"
            @click="go(it.to)"
          >
            <component :is="it.icon" :size="16" class="cmdk-item-icon" />
            <span class="cmdk-item-label">{{ it.label }}</span>
            <span class="cmdk-item-section">{{ it.section }}</span>
          </button>
        </template>

        <template v-if="puedeBuscar">
          <div v-if="propietarios.length" class="cmdk-group-label">
            Propietarios
            <span v-if="buscando" class="cmdk-spin">·</span>
          </div>
          <button
            v-for="cl in propietarios"
            :key="'cli-' + cl.id"
            :class="['cmdk-item', { active: flatIndex(cl, 'cliente') === activeIndex }]"
            :data-idx="flatIndex(cl, 'cliente')"
            @mousemove="activeIndex = flatIndex(cl, 'cliente')"
            @click="irACliente(cl)"
          >
            <IdCard :size="16" class="cmdk-item-icon" />
            <span class="cmdk-item-label">{{ cl.nombre_completo }}</span>
            <span class="cmdk-item-doc">{{ cl.numero_documento }}</span>
          </button>

          <div v-if="pacientes.length" class="cmdk-group-label">Pacientes</div>
          <button
            v-for="m in pacientes"
            :key="'mas-' + m.id"
            :class="['cmdk-item', { active: flatIndex(m, 'mascota') === activeIndex }]"
            :data-idx="flatIndex(m, 'mascota')"
            @mousemove="activeIndex = flatIndex(m, 'mascota')"
            @click="irAPaciente(m)"
          >
            <PawPrint :size="16" class="cmdk-item-icon" />
            <span class="cmdk-item-label">{{ m.nombre }}</span>
            <span class="cmdk-item-doc">{{ m.especie }} · {{ m.propietario }}</span>
          </button>
        </template>

        <div v-if="isEmpty" class="cmdk-empty">
          <template v-if="buscando">Buscando…</template>
          <template v-else-if="query.trim()">Sin resultados para “{{ query.trim() }}”</template>
          <template v-else>Escribe para buscar módulos, propietarios o pacientes</template>
        </div>

        <div class="cmdk-foot">
          <span><kbd>↑</kbd><kbd>↓</kbd> navegar</span>
          <span><kbd>↵</kbd> abrir</span>
          <span><kbd>Esc</kbd> cerrar</span>
        </div>
      </div>
    </Transition>
  </div>
</template>

<script setup>
import { ref, computed, watch, nextTick, onMounted, onBeforeUnmount } from "vue";
import { useRouter } from "vue-router";
import { Search, IdCard, PawPrint } from "lucide-vue-next";
import { useAuth } from "../../composables/useAuth.js";
import { visibleNavItems } from "../../config/navigation.js";
import { clientesApi } from "../../../modules/clientes/api/clientes.api.js";

const router = useRouter();
const { hasPermission, isSuperAdmin } = useAuth();

const open = ref(false);
const query = ref("");
const activeIndex = ref(0);
const rootRef = ref(null);
const inputRef = ref(null);
const listRef = ref(null);

const propietarios = ref([]);
const pacientes = ref([]);
const buscando = ref(false);
let searchToken = 0;
let debounceTimer = null;

const isMac = typeof navigator !== "undefined" && /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
const shortcut = isMac ? "⌘K" : "Ctrl K";

const puedeBuscar = computed(() => hasPermission("clientes:listar"));
const allNav = computed(() => visibleNavItems(hasPermission, isSuperAdmin.value));

// Filtra la navegación por label/keywords/sección con el término escrito.
const navResults = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) return allNav.value;
  return allNav.value.filter((it) => {
    const hay = `${it.label} ${it.section} ${it.keywords || ""}`.toLowerCase();
    return q.split(/\s+/).every((tok) => hay.includes(tok));
  });
});

// Índice plano para navegación por teclado: módulos → propietarios → pacientes.
function flatIndex(item, tipo = "nav") {
  if (tipo === "cliente") return navResults.value.length + propietarios.value.indexOf(item);
  if (tipo === "mascota") {
    return navResults.value.length + propietarios.value.length + pacientes.value.indexOf(item);
  }
  return navResults.value.indexOf(item);
}
const totalResults = computed(
  () => navResults.value.length + propietarios.value.length + pacientes.value.length,
);
const isEmpty = computed(() => totalResults.value === 0);

function move(delta) {
  if (!totalResults.value) return;
  activeIndex.value = (activeIndex.value + delta + totalResults.value) % totalResults.value;
  nextTick(() => {
    listRef.value?.querySelector(`[data-idx="${activeIndex.value}"]`)?.scrollIntoView({ block: "nearest" });
  });
}

function chooseActive() {
  const idx = activeIndex.value;
  const nNav = navResults.value.length;
  const nCli = propietarios.value.length;

  if (idx < nNav) {
    const it = navResults.value[idx];
    if (it) go(it.to);
  } else if (idx < nNav + nCli) {
    const cl = propietarios.value[idx - nNav];
    if (cl) irACliente(cl);
  } else {
    const m = pacientes.value[idx - nNav - nCli];
    if (m) irAPaciente(m);
  }
}

function go(to) {
  reset();
  router.push(to);
}

function irACliente(cl) {
  reset();
  router.push(`/clientes/${cl.id}`);
}

function irAPaciente(m) {
  reset();
  router.push(`/pacientes/${m.id}`);
}

function reset() {
  open.value = false;
  query.value = "";
  propietarios.value = [];
  pacientes.value = [];
  activeIndex.value = 0;
  inputRef.value?.blur();
}

function closeAndBlur() {
  open.value = false;
  inputRef.value?.blur();
}

// Búsqueda con debounce; el token evita que una respuesta lenta pise a una nueva.
// fn_cliente_buscar ya trae las mascotas anidadas: aquí se aplanan para poder
// saltar directo a la ficha del paciente, que es lo que más se busca en recepción.
watch(query, (q) => {
  activeIndex.value = 0;
  clearTimeout(debounceTimer);
  const term = q.trim();
  if (!puedeBuscar.value || term.length < 2) {
    propietarios.value = [];
    pacientes.value = [];
    buscando.value = false;
    return;
  }
  buscando.value = true;
  const myToken = ++searchToken;
  debounceTimer = setTimeout(async () => {
    try {
      const r = await clientesApi.buscar(term, 6);
      if (myToken !== searchToken) return;
      const filas = r.data ?? [];
      propietarios.value = filas;
      pacientes.value = filas.flatMap((c) =>
        (c.mascotas ?? []).map((m) => ({ ...m, propietario: c.nombre_completo })),
      ).slice(0, 8);
    } catch {
      if (myToken === searchToken) {
        propietarios.value = [];
        pacientes.value = [];
      }
    } finally {
      if (myToken === searchToken) buscando.value = false;
    }
  }, 220);
});

// ⌘K / Ctrl+K enfoca (o cierra) el buscador desde cualquier pantalla.
function onKeydown(e) {
  if ((e.metaKey || e.ctrlKey) && (e.key === "k" || e.key === "K")) {
    e.preventDefault();
    if (open.value) {
      closeAndBlur();
    } else {
      open.value = true;
      nextTick(() => inputRef.value?.focus());
    }
  }
}

// Click fuera del componente cierra el dropdown.
function onClickFuera(e) {
  if (open.value && rootRef.value && !rootRef.value.contains(e.target)) {
    open.value = false;
  }
}

onMounted(() => {
  document.addEventListener("keydown", onKeydown);
  document.addEventListener("mousedown", onClickFuera);
});
onBeforeUnmount(() => {
  clearTimeout(debounceTimer);
  document.removeEventListener("keydown", onKeydown);
  document.removeEventListener("mousedown", onClickFuera);
});
</script>

<style scoped>
.cmdk {
  position: relative;
  display: inline-flex;
}

/* Caja de búsqueda (replica el estilo del topbar, ahora como input real). */
.cmdk-box {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 320px;
  background: var(--bg);
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 6px 12px;
  transition: border-color 0.12s, box-shadow 0.12s, background 0.12s;
}
.cmdk-box:hover { border-color: var(--line-strong); }
.cmdk-box.active {
  border-color: var(--emerald);
  background: var(--bg-elev);
  box-shadow: 0 0 0 3px var(--emerald-soft);
}
.cmdk-box-input {
  flex: 1;
  min-width: 0;
  border: none;
  outline: none;
  background: transparent;
  font-size: 13px;
  color: var(--ink);
}
.cmdk-box-input::placeholder { color: var(--ink-4); }
.cmdk-kbd {
  font-family: var(--font-mono);
  font-size: 10.5px;
  background: var(--bg-elev);
  border: 1px solid var(--line);
  border-radius: 4px;
  padding: 1px 5px;
  color: var(--ink-3);
  font-weight: 500;
  flex-shrink: 0;
}

/* Dropdown de resultados anclado justo debajo de la caja. */
.cmdk-dropdown {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  width: 420px;
  max-width: calc(100vw - 32px);
  background: var(--bg-elev, #fff);
  border: 1px solid var(--line, #e2e8f0);
  border-radius: 12px;
  box-shadow: 0 16px 44px rgba(0, 0, 0, 0.18);
  overflow: hidden;
  display: flex;
  flex-direction: column;
  max-height: min(70vh, 480px);
  z-index: 120;
  padding: 6px;
}

.cmdk-group-label {
  font-size: 10.5px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-weight: 600;
  color: var(--ink-4, #94a3b8);
  padding: 10px 10px 4px;
}
.cmdk-spin { animation: cmdk-blink 0.9s steps(2) infinite; }
@keyframes cmdk-blink { 50% { opacity: 0.2; } }

.cmdk-item {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 9px 10px;
  border: none;
  background: none;
  border-radius: 9px;
  cursor: pointer;
  text-align: left;
  color: var(--ink-2, #334155);
}
.cmdk-item.active { background: var(--emerald-soft, rgba(31, 201, 122, 0.12)); }
.cmdk-item-icon { flex: 0 0 auto; color: var(--ink-3, #64748b); }
.cmdk-item.active .cmdk-item-icon { color: var(--emerald, #1fc97a); }
.cmdk-item-label {
  flex: 1;
  font-size: 13.5px;
  color: var(--ink, #0f172a);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.cmdk-item-section { font-size: 11px; color: var(--ink-4, #94a3b8); }
.cmdk-item-doc {
  font-family: var(--font-mono);
  font-size: 11.5px;
  color: var(--ink-3, #64748b);
}

.cmdk-empty {
  padding: 26px 16px;
  text-align: center;
  font-size: 13px;
  color: var(--ink-4, #94a3b8);
}

.cmdk-foot {
  display: flex;
  gap: 16px;
  padding: 9px 8px 4px;
  margin-top: 4px;
  border-top: 1px solid var(--line, #e2e8f0);
  font-size: 11px;
  color: var(--ink-4, #94a3b8);
}
.cmdk-foot kbd {
  font-family: var(--font-mono);
  font-size: 10px;
  border: 1px solid var(--line, #e2e8f0);
  border-radius: 4px;
  padding: 0 4px;
  margin-right: 3px;
  color: var(--ink-3, #64748b);
  background: var(--bg, #f8fafc);
}

.cmdk-enter-active,
.cmdk-leave-active { transition: opacity 0.14s ease, transform 0.14s ease; transform-origin: top right; }
.cmdk-enter-from,
.cmdk-leave-to { opacity: 0; transform: translateY(-6px) scale(0.98); }
</style>
