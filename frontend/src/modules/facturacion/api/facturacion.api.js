import { apiFetch, qs } from "../../../shared/api/client.js";

export const facturacionApi = {
  listar: (params = {}) => apiFetch(`/facturacion${qs(params)}`),
  obtener: (id) => apiFetch(`/facturacion/${id}`),
  /** Sin `items` factura todo lo pendiente del cliente. */
  emitir: (payload) => apiFetch("/facturacion", { method: "POST", body: payload }),
  anular: (id, motivo) => apiFetch(`/facturacion/${id}/anular`, { method: "PATCH", body: { motivo } }),
  /** Sin `items` acredita el comprobante entero. */
  notaCredito: (payload) => apiFetch("/facturacion/notas-credito", { method: "POST", body: payload }),
  cuentasPorCobrar: (params = {}) => apiFetch(`/facturacion/cuentas-por-cobrar${qs(params)}`),
};
