import { ref, watch } from "vue";

const KEY = "vet_theme";

function detectInitial() {
  const saved = localStorage.getItem(KEY);
  if (saved === "dark" || saved === "light") return saved;
  if (typeof window !== "undefined" && window.matchMedia) {
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }
  return "light";
}

const theme = ref(detectInitial());

function apply(t) {
  document.documentElement.setAttribute("data-theme", t);
}

apply(theme.value);

watch(theme, (v) => {
  localStorage.setItem(KEY, v);
  apply(v);
});

function toggle() {
  theme.value = theme.value === "dark" ? "light" : "dark";
}

function setTheme(t) {
  theme.value = t === "dark" ? "dark" : "light";
}

export function useTheme() {
  return { theme, toggle, setTheme };
}

// Helper para inicializar antes del mount y evitar flash
export function initThemeEarly() {
  apply(detectInitial());
}
