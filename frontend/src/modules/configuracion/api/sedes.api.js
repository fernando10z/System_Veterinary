import { apiFetch, qs } from "../../../shared/api/client.js";

export const sedesApi = {
  listar: (params = {}) => apiFetch(`/sedes${qs(params)}`),
  guardar: (payload) => apiFetch("/sedes", { method: "POST", body: payload }),
  eliminar: (id) => apiFetch(`/sedes/${id}`, { method: "DELETE" }),
};
