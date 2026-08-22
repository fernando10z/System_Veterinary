import Swal from "sweetalert2";

/**
 * Wrapper de sweetalert2 estilado con el sistema (emerald + dark mode).
 * Reemplaza alert / confirm / prompt nativos.
 *
 * Uso:
 *   import { notify } from "@/shared/composables/useNotify.js";
 *   notify.success("Guardado");
 *   if (await notify.confirm("¿Eliminar?")) ...
 *   const v = await notify.prompt("Motivo");
 */

const baseColors = {
  confirmEmerald: "#07B162",
  confirmDeep: "#058F4F",
  cancel: "#9AA29F",
  danger: "#DC4040",
  warn: "#E89A1F",
  info: "#2D7EE5",
};

function basePopupClass() {
  return "vet-sweet";
}

function darkMode() {
  return document.documentElement.getAttribute("data-theme") === "dark";
}

const baseOpts = (extra = {}) => ({
  buttonsStyling: false,
  customClass: {
    popup: basePopupClass() + (darkMode() ? " vet-sweet--dark" : ""),
    title: "vet-sweet__title",
    htmlContainer: "vet-sweet__body",
    actions: "vet-sweet__actions",
    confirmButton: "vet-sweet__btn vet-sweet__btn--primary",
    cancelButton: "vet-sweet__btn vet-sweet__btn--ghost",
    denyButton: "vet-sweet__btn vet-sweet__btn--danger",
    icon: "vet-sweet__icon",
    input: "vet-sweet__input",
  },
  reverseButtons: true,
  showClass: { popup: "vet-sweet-anim-in" },
  hideClass: { popup: "vet-sweet-anim-out" },
  ...extra,
});

export const notify = {
  success(title, text) {
    return Swal.fire(baseOpts({
      icon: "success",
      title,
      text: text || "",
      iconColor: baseColors.confirmEmerald,
      timer: 2400,
      timerProgressBar: true,
      showConfirmButton: false,
    }));
  },

  error(title, text) {
    return Swal.fire(baseOpts({
      icon: "error",
      title,
      text: text || "",
      iconColor: baseColors.danger,
      confirmButtonText: "Entendido",
    }));
  },

  warn(title, text) {
    return Swal.fire(baseOpts({
      icon: "warning",
      title,
      text: text || "",
      iconColor: baseColors.warn,
      confirmButtonText: "Entendido",
    }));
  },

  info(title, text) {
    return Swal.fire(baseOpts({
      icon: "info",
      title,
      text: text || "",
      iconColor: baseColors.info,
      confirmButtonText: "Cerrar",
    }));
  },

  /**
   * Devuelve true si el usuario confirmó.
   * @param {string} title
   * @param {string} text
   * @param {object} opts - { confirmText, cancelText, icon, danger }
   */
  async confirm(title, text = "", opts = {}) {
    const r = await Swal.fire(baseOpts({
      icon: opts.icon ?? "question",
      title,
      text,
      iconColor: opts.danger ? baseColors.danger : baseColors.warn,
      showCancelButton: true,
      confirmButtonText: opts.confirmText ?? "Confirmar",
      cancelButtonText: opts.cancelText ?? "Cancelar",
      customClass: {
        ...baseOpts().customClass,
        confirmButton: opts.danger
          ? "vet-sweet__btn vet-sweet__btn--danger"
          : "vet-sweet__btn vet-sweet__btn--primary",
        cancelButton: "vet-sweet__btn vet-sweet__btn--ghost",
      },
    }));
    return r.isConfirmed;
  },

  /**
   * Devuelve el string ingresado o null si canceló.
   * @param {string} title
   * @param {object} opts - { text, placeholder, inputType, confirmText, validator }
   */
  async prompt(title, opts = {}) {
    const r = await Swal.fire(baseOpts({
      title,
      text: opts.text || "",
      icon: opts.icon,
      input: opts.inputType || "text",
      inputPlaceholder: opts.placeholder || "",
      inputValue: opts.defaultValue || "",
      showCancelButton: true,
      confirmButtonText: opts.confirmText || "Aceptar",
      cancelButtonText: opts.cancelText || "Cancelar",
      inputValidator: opts.validator,
    }));
    return r.isConfirmed ? r.value : null;
  },

  /**
   * Selector con opciones predefinidas (radios estilo card).
   * @param {string} title
   * @param {Array<{value, label, description?}>} options
   * @param {string} defaultValue
   */
  async select(title, options = [], defaultValue = null) {
    const inputOptions = {};
    for (const o of options) inputOptions[o.value] = o.label;
    const r = await Swal.fire(baseOpts({
      title,
      input: "radio",
      inputOptions,
      inputValue: defaultValue,
      showCancelButton: true,
      confirmButtonText: "Aceptar",
      cancelButtonText: "Cancelar",
      inputValidator: (v) => (!v ? "Elige una opción" : undefined),
    }));
    return r.isConfirmed ? r.value : null;
  },

  toast(message, type = "success") {
    const iconColor =
      type === "error" ? baseColors.danger :
      type === "warn" ? baseColors.warn :
      type === "info" ? baseColors.info :
      baseColors.confirmEmerald;
    return Swal.fire({
      toast: true,
      position: "top-end",
      backdrop: false, // un toast no debe oscurecer la pantalla
      icon: type,
      iconColor,
      title: message,
      showConfirmButton: false,
      timer: 2400,
      timerProgressBar: true,
      buttonsStyling: false,
      customClass: {
        popup: "vet-sweet vet-sweet--toast" + (darkMode() ? " vet-sweet--dark" : ""),
        title: "vet-sweet__title",
      },
    });
  },
};

export default notify;
