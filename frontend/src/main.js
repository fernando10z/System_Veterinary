import { createApp } from "vue";
import App from "./App.vue";
import router from "./router/index.js";
import { initThemeEarly } from "./shared/composables/useTheme.js";
import "./styles/globals.css";
import "./styles/patterns.css";

// Aplica el tema antes del mount para evitar el flash de color al recargar.
initThemeEarly();

createApp(App).use(router).mount("#app");
