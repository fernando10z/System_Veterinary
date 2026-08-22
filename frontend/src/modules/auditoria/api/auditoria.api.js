import { apiFetch, qs } from "../../../shared/api/client.js";

export const auditoriaApi = {
  listar: (params = {}) => apiFetch(`/auditoria${qs(params)}`),
};

export const notificacionesApi = {
  listar: (params = {}) => apiFetch(`/notificaciones${qs(params)}`),
  marcarLeida: (id) => apiFetch(`/notificaciones/${id}/leida`, { method: "PATCH" }),
  marcarTodas: () => apiFetch("/notificaciones/leidas", { method: "PATCH" }),
};
