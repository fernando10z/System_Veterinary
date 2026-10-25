import { createApp } from "vue";
import App from "./App.vue";
import router from "./router/index.js";
import { initThemeEarly } from "./shared/composables/useTheme.js";
import { dialogo } from "./shared/directives/dialogo.js";
import { notify } from "./shared/composables/useNotify.js";
// Fuentes servidas por el propio sitio (sin Google Fonts): IBM Plex Sans para
// títulos y cifras, Ubuntu para el texto, IBM Plex Mono solo para identificadores.
import "@fontsource/ibm-plex-sans/600.css";
import "@fontsource/ibm-plex-sans/700.css";
import "@fontsource/ubuntu/400.css";
import "@fontsource/ubuntu/500.css";
import "@fontsource/ubuntu/700.css";
import "@fontsource/ibm-plex-mono/400.css";
import "./styles/globals.css";
import "./styles/patterns.css";
import "./shared/print/print.css";

// Aplica el tema antes del mount para evitar el flash de color al recargar.
initThemeEarly();

const app = createApp(App).use(router).directive("dialogo", dialogo);

// Red de seguridad: un error no capturado en una pantalla (una llamada a la API
// sin try/catch) se avisa en vez de dejar un botón que "no hace nada".
app.config.errorHandler = (err, _inst, info) => {
  console.error(err, info);
  notify.toast(err?.message || "Ocurrió un error inesperado", "error");
};
window.addEventListener("unhandledrejection", (e) => {
  const msg = e.reason?.message;
  if (!msg) return;
  console.error(e.reason);
  notify.toast(msg, "error");
});

// Un deploy nuevo invalida los chunks lazy de la versión anterior: si una
// pantalla no carga por eso, se recarga una vez para traer la versión actual.
router.onError((err, to) => {
  if (/Failed to fetch dynamically imported module|Importing a module script failed/i.test(err?.message || "")) {
    const k = "vet_chunk_reload";
    try {
      if (sessionStorage.getItem(k) !== to.fullPath) {
        sessionStorage.setItem(k, to.fullPath);
        window.location.assign(to.fullPath);
      }
    } catch { /* sin sessionStorage: no se reintenta */ }
  }
});

app.mount("#app");
