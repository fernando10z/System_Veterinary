import { apiFetch, qs } from "../../../shared/api/client.js";

export const rrhhApi = {
  equipo: (params = {}) => apiFetch(`/rrhh/equipo${qs(params)}`),
  disponibilidad: (params) => apiFetch(`/rrhh/disponibilidad${qs(params)}`),
  guardarDisponibilidad: (payload) =>
    apiFetch("/rrhh/disponibilidad", { method: "POST", body: payload }),
  eliminarDisponibilidad: (id) =>
    apiFetch(`/rrhh/disponibilidad/${id}`, { method: "DELETE" }),

  asistencia: (params) => apiFetch(`/rrhh/asistencia${qs(params)}`),
  /** Un solo endpoint: marca entrada o salida según el estado del día. */
  marcarAsistencia: (userId) =>
    apiFetch("/rrhh/asistencia/marcar", { method: "POST", body: { userId } }),

  permisos: (params = {}) => apiFetch(`/rrhh/permisos${qs(params)}`),
  solicitarPermiso: (payload) => apiFetch("/rrhh/permisos", { method: "POST", body: payload }),
  resolverPermiso: (id, payload) =>
    apiFetch(`/rrhh/permisos/${id}/resolver`, { method: "PATCH", body: payload }),

  guardarContrato: (payload) => apiFetch("/rrhh/contratos", { method: "POST", body: payload }),
  registrarEvaluacion: (payload) =>
    apiFetch("/rrhh/evaluaciones", { method: "POST", body: payload }),
};
