import { ref } from "vue";

const KEY = "vet_sidebar_collapsed";
const MOVIL = "(max-width: 720px)";

function leer() {
  try { return localStorage.getItem(KEY) === "true"; } catch { return false; }
}
function guardar(v) {
  try { localStorage.setItem(KEY, String(v)); } catch { /* sin storage */ }
}

const state = ref(leer());

// En pantallas angostas (celular, tablet vertical chica) el menú no ocupa una
// columna: es un panel que se abre encima del contenido con el botón de menú.
const mq = typeof window !== "undefined" && window.matchMedia ? window.matchMedia(MOVIL) : null;
const isMobile = ref(!!mq?.matches);
const mobileOpen = ref(false);
mq?.addEventListener?.("change", (e) => {
  isMobile.value = e.matches;
  if (!e.matches) mobileOpen.value = false;
});

function toggle() {
  if (isMobile.value) {
    mobileOpen.value = !mobileOpen.value;
    return;
  }
  state.value = !state.value;
  guardar(state.value);
}

function setCollapsed(val) {
  state.value = !!val;
  guardar(state.value);
}

function closeMobile() {
  mobileOpen.value = false;
}

export function useSidebar() {
  return {
    isCollapsed: state,
    isMobile,
    mobileOpen,
    toggle,
    setCollapsed,
    closeMobile,
  };
}
