import { apiFetch, qs } from "../../../shared/api/client.js";

export const planesApi = {
  listar: (params = {}) => apiFetch(`/planes${qs(params)}`),
  guardar: (payload) => apiFetch("/planes", { method: "POST", body: payload }),
  eliminar: (id) => apiFetch(`/planes/${id}`, { method: "DELETE" }),

  suscripciones: (params = {}) => apiFetch(`/planes/suscripciones/listar${qs(params)}`),
  suscribir: (payload) => apiFetch("/planes/suscripciones", { method: "POST", body: payload }),
  cancelar: (id, motivo) =>
    apiFetch(`/planes/suscripciones/${id}/cancelar`, { method: "PATCH", body: { motivo } }),
  /** Qué le queda al paciente de su plan. */
  estadoMascota: (mascotaId) => apiFetch(`/planes/mascota/${mascotaId}`),
  vencer: () => apiFetch("/planes/vencer", { method: "POST" }),
};

export const PERIODICIDADES = [
  { v: "mensual", t: "Mensual" },
  { v: "trimestral", t: "Trimestral" },
  { v: "semestral", t: "Semestral" },
  { v: "anual", t: "Anual" },
];
