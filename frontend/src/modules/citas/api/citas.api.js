import { apiFetch, qs } from "../../../shared/api/client.js";

export const citasApi = {
  listar: (params = {}) => apiFetch(`/citas${qs(params)}`),
  obtener: (id) => apiFetch(`/citas/${id}`),
  /** Resumen de la sala de espera del día. */
  agendaDia: (fecha) => apiFetch(`/citas/agenda-dia${qs({ fecha })}`),
  /** Huecos libres de un veterinario en una fecha. */
  disponibilidad: (params) => apiFetch(`/citas/disponibilidad${qs(params)}`),
  crear: (payload) => apiFetch("/citas", { method: "POST", body: payload }),
  reprogramar: (id, payload) =>
    apiFetch(`/citas/${id}/reprogramar`, { method: "PATCH", body: payload }),
  cambiarEstado: (id, estado, motivo) =>
    apiFetch(`/citas/${id}/estado`, { method: "PATCH", body: { estado, motivo } }),
  eliminar: (id) => apiFetch(`/citas/${id}`, { method: "DELETE" }),

  // ---- Sala de espera y cola de cupos ----
  /** Quién está ahora en la clínica, ordenado por gravedad. */
  salaEspera: (params = {}) => apiFetch(`/citas/sala-espera${qs(params)}`),
  /** Con `cita_id` marca la llegada; sin él, atención sin cita previa. */
  registrarLlegada: (payload) => apiFetch("/citas/llegada", { method: "POST", body: payload }),
  listaEspera: (params = {}) => apiFetch(`/citas/lista-espera${qs(params)}`),
  anotarListaEspera: (payload) =>
    apiFetch("/citas/lista-espera", { method: "POST", body: payload }),
  resolverListaEspera: (id) =>
    apiFetch(`/citas/lista-espera/${id}/resolver`, { method: "PATCH" }),
};
