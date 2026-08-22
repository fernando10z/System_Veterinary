import { apiFetch, qs } from "../../../shared/api/client.js";

export const empresasApi = {
  listar: (params = {}) => apiFetch(`/empresas${qs(params)}`),
  /** Sede activa del usuario. */
  actual: () => apiFetch("/empresas/actual"),
  obtener: (id) => apiFetch(`/empresas/${id}`),
  crear: (payload) => apiFetch("/empresas", { method: "POST", body: payload }),
  actualizar: (id, payload) => apiFetch(`/empresas/${id}`, { method: "PATCH", body: payload }),
};
