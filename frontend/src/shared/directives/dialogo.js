import Swal from "sweetalert2";
import { notify } from "@/shared/composables/useNotify.js";

/**
 * v-dialogo: comportamiento común de todos los modales (.modal-back).
 *
 *   <div class="modal-back" v-dialogo="() => $emit('close')">
 *
 * - Clic en el fondo: cierra SOLO si el formulario está intacto. Si ya se
 *   escribió algo, el diálogo "tiembla" y no se pierde nada (antes un clic
 *   distraído fuera del modal borraba la ficha a medio llenar).
 * - Escape: cierra el diálogo de más arriba; si hay cambios, pide confirmar.
 * - "Sucio" = hubo algún input/change dentro del diálogo desde que se abrió.
 *
 * Con `v-dialogo.estricto` el fondo nunca cierra (cobros, cierre de caja).
 */

const pila = [];

function marcarSucio(e) {
  // Los buscadores (autocompletes) no cuentan como datos del formulario.
  if (e.target?.closest?.("[data-no-dirty]")) return;
  this.__dialogo.sucio = true;
}

async function intentarCerrar(el, origen) {
  const st = el.__dialogo;
  if (!st || st.confirmando) return;
  if (origen === "fondo" && (st.estricto || st.sucio)) {
    const m = el.querySelector(".modal");
    if (m) {
      m.classList.remove("modal-shake");
      void m.offsetWidth; // reinicia la animación
      m.classList.add("modal-shake");
    }
    return;
  }
  if (st.sucio) {
    st.confirmando = true;
    const ok = await notify.confirm(
      "¿Descartar los cambios?",
      "Lo que escribiste en este formulario no se ha guardado.",
      { confirmText: "Descartar", cancelText: "Seguir editando", danger: true, icon: "warning" },
    );
    st.confirmando = false;
    if (!ok) return;
  }
  st.cerrar?.();
}

function onKey(e) {
  if (e.key !== "Escape" || !pila.length) return;
  // Si hay un SweetAlert abierto (que no sea un toast), el Escape es suyo.
  if (Swal.isVisible() && !document.body.classList.contains("swal2-toast-shown")) return;
  const el = pila[pila.length - 1];
  e.preventDefault();
  intentarCerrar(el, "escape");
}

function onFondo(e) {
  if (e.target !== e.currentTarget) return;
  intentarCerrar(e.currentTarget, "fondo");
}

export const dialogo = {
  mounted(el, binding) {
    el.__dialogo = {
      cerrar: binding.value,
      sucio: false,
      estricto: !!binding.modifiers.estricto,
      confirmando: false,
      marcar: null,
    };
    el.__dialogo.marcar = marcarSucio.bind(el);
    el.addEventListener("input", el.__dialogo.marcar);
    el.addEventListener("change", el.__dialogo.marcar);
    el.addEventListener("click", onFondo);
    el.setAttribute("role", "dialog");
    el.setAttribute("aria-modal", "true");
    if (!pila.length) window.addEventListener("keydown", onKey);
    pila.push(el);
  },
  updated(el, binding) {
    if (el.__dialogo) el.__dialogo.cerrar = binding.value;
  },
  unmounted(el) {
    const i = pila.indexOf(el);
    if (i >= 0) pila.splice(i, 1);
    if (!pila.length) window.removeEventListener("keydown", onKey);
    if (el.__dialogo) {
      el.removeEventListener("input", el.__dialogo.marcar);
      el.removeEventListener("change", el.__dialogo.marcar);
    }
    el.removeEventListener("click", onFondo);
    delete el.__dialogo;
  },
};

/** Marca el diálogo como limpio (p. ej. después de guardar sin cerrar). */
export function dialogoLimpio(el) {
  if (el?.__dialogo) el.__dialogo.sucio = false;
}

export default dialogo;
