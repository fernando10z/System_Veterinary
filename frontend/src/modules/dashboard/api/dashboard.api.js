import { apiFetch, qs } from "../../../shared/api/client.js";

export const dashboardApi = {
  resumen: (params = {}) => apiFetch(`/dashboard${qs(params)}`),
  recordatorios: (dias = 7) => apiFetch(`/dashboard/recordatorios${qs({ dias })}`),
  completarRecordatorio: (id) =>
    apiFetch(`/dashboard/recordatorios/${id}/completar`, { method: "PATCH" }),
  /** Deja el contacto en la bitácora del propietario. */
  contactarRecordatorio: (id, payload = {}) =>
    apiFetch(`/dashboard/recordatorios/${id}/contactar`, { method: "PATCH", body: payload }),
  generarRecordatoriosCitas: (dias = 1) =>
    apiFetch(`/dashboard/recordatorios/generar-citas${qs({ dias })}`, { method: "POST" }),
  plantillas: () => apiFetch("/dashboard/plantillas"),
  guardarPlantilla: (payload) =>
    apiFetch("/dashboard/plantillas", { method: "POST", body: payload }),
};
