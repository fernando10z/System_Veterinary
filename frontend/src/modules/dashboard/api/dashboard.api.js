import { apiFetch, qs } from "../../../shared/api/client.js";

export const dashboardApi = {
  resumen: (params = {}) => apiFetch(`/dashboard${qs(params)}`),
  recordatorios: (dias = 7) => apiFetch(`/dashboard/recordatorios${qs({ dias })}`),
  completarRecordatorio: (id) =>
    apiFetch(`/dashboard/recordatorios/${id}/completar`, { method: "PATCH" }),
};
