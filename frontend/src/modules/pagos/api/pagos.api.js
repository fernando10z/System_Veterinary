import { apiFetch, qs } from "../../../shared/api/client.js";

export const pagosApi = {
  listar: (params = {}) => apiFetch(`/pagos${qs(params)}`),
  registrar: (payload) => apiFetch("/pagos", { method: "POST", body: payload }),
  anular: (id, motivo) => apiFetch(`/pagos/${id}/anular`, { method: "PATCH", body: { motivo } }),
};

export const cajaApi = {
  actual: () => apiFetch("/caja/actual"),
  listar: (params = {}) => apiFetch(`/caja${qs(params)}`),
  abrir: (payload) => apiFetch("/caja/abrir", { method: "POST", body: payload }),
  movimiento: (payload) => apiFetch("/caja/movimientos", { method: "POST", body: payload }),
  /** Arqueo: compara lo contado contra lo esperado. */
  cerrar: (id, payload) => apiFetch(`/caja/${id}/cerrar`, { method: "PATCH", body: payload }),
};
