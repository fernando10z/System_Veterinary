import { apiFetch, qs } from "../../../shared/api/client.js";

export const peluqueriaApi = {
  /** Tablero del día: quién está dentro y en qué estado. */
  listar: (params = {}) => apiFetch(`/peluqueria${qs(params)}`),
  obtener: (id) => apiFetch(`/peluqueria/${id}`),
  /** Recepción del animal: servicios pedidos y estado en que llegó. */
  recibir: (payload) => apiFetch("/peluqueria", { method: "POST", body: payload }),
  iniciar: (id) => apiFetch(`/peluqueria/${id}/iniciar`, { method: "PATCH" }),
  /** Lo que se le vio mientras se le bañaba. Entra en la historia clínica. */
  hallazgo: (id, payload) =>
    apiFetch(`/peluqueria/${id}/hallazgos`, { method: "POST", body: payload }),
  atenderHallazgo: (id) =>
    apiFetch(`/peluqueria/hallazgos/${id}/atender`, { method: "PATCH" }),
  terminar: (id, payload = {}) =>
    apiFetch(`/peluqueria/${id}/terminar`, { method: "PATCH", body: payload }),
  entregar: (id, payload = {}) =>
    apiFetch(`/peluqueria/${id}/entregar`, { method: "PATCH", body: payload }),
  cancelar: (id, motivo) =>
    apiFetch(`/peluqueria/${id}/cancelar`, { method: "PATCH", body: { motivo } }),
};

/** Los hallazgos, con el nombre que usa quien los teclea. */
export const HALLAZGOS = [
  { v: "pulgas", t: "Pulgas" },
  { v: "garrapatas", t: "Garrapatas" },
  { v: "nudos_severos", t: "Nudos severos" },
  { v: "heridas", t: "Heridas" },
  { v: "otitis", t: "Otitis" },
  { v: "mal_olor_oidos", t: "Mal olor de oídos" },
  { v: "problemas_piel", t: "Problemas de piel" },
  { v: "bultos", t: "Bultos o nódulos" },
  { v: "unias_encarnadas", t: "Uñas encarnadas" },
  { v: "sarro", t: "Sarro dental" },
  { v: "secrecion_ocular", t: "Secreción ocular" },
  { v: "delgadez", t: "Delgadez" },
  { v: "agresividad", t: "Agresividad" },
  { v: "otro", t: "Otro" },
];

export const CONDICION_PELAJE = ["normal", "nudos_leves", "nudos_severos", "apelmazado"];
export const TEMPERAMENTOS = ["docil", "nervioso", "agresivo", "requiere_bozal"];
