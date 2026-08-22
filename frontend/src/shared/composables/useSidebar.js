import { ref } from "vue";

const KEY = "vet_sidebar_collapsed";
const state = ref(localStorage.getItem(KEY) === "true");

function toggle() {
  state.value = !state.value;
  localStorage.setItem(KEY, String(state.value));
}

function setCollapsed(val) {
  state.value = !!val;
  localStorage.setItem(KEY, String(state.value));
}

export function useSidebar() {
  return {
    isCollapsed: state,
    toggle,
    setCollapsed,
  };
}
