import { apiFetch, qs } from "../../../shared/api/client.js";

export const comprasApi = {
  proveedores: (params = {}) => apiFetch(`/compras/proveedores${qs(params)}`),
  guardarProveedor: (payload) =>
    apiFetch("/compras/proveedores", { method: "POST", body: payload }),
  eliminarProveedor: (id) => apiFetch(`/compras/proveedores/${id}`, { method: "DELETE" }),
  guardarContacto: (payload) =>
    apiFetch("/compras/proveedores/contactos", { method: "POST", body: payload }),

  ordenes: (params = {}) => apiFetch(`/compras/ordenes${qs(params)}`),
  crearOrden: (payload) => apiFetch("/compras/ordenes", { method: "POST", body: payload }),
  /** Recibir mercadería: mueve inventario y crea los lotes. */
  recibirOrden: (id, recepcion) =>
    apiFetch(`/compras/ordenes/${id}/recibir`, { method: "POST", body: { recepcion } }),
  cambiarEstadoOrden: (id, estado) =>
    apiFetch(`/compras/ordenes/${id}/estado`, { method: "PATCH", body: { estado } }),

  pagos: (params = {}) => apiFetch(`/compras/pagos${qs(params)}`),
  registrarPago: (payload) => apiFetch("/compras/pagos", { method: "POST", body: payload }),
};
