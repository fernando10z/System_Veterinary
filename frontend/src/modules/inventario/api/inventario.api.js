import { apiFetch, qs } from "../../../shared/api/client.js";

export const inventarioApi = {
  productos: (params = {}) => apiFetch(`/inventario/productos${qs(params)}`),
  guardarProducto: (payload) =>
    apiFetch("/inventario/productos", { method: "POST", body: payload }),
  eliminarProducto: (id) => apiFetch(`/inventario/productos/${id}`, { method: "DELETE" }),
  /** Stock crítico, lotes por vencer y vencidos. */
  alertas: () => apiFetch("/inventario/alertas"),
  almacenes: () => apiFetch("/inventario/almacenes"),
  movimientos: (params = {}) => apiFetch(`/inventario/movimientos${qs(params)}`),
  registrarMovimiento: (payload) =>
    apiFetch("/inventario/movimientos", { method: "POST", body: payload }),
  registrarLote: (payload) => apiFetch("/inventario/lotes", { method: "POST", body: payload }),
};
