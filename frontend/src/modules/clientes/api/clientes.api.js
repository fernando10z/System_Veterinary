import { apiFetch, qs } from "../../../shared/api/client.js";

export const clientesApi = {
  listar: (params = {}) => apiFetch(`/clientes${qs(params)}`),
  obtener: (id) => apiFetch(`/clientes/${id}`),
  /** Autocompletar: busca por nombre, documento, teléfono o nombre de mascota. */
  buscar: (q, limit = 20) => apiFetch(`/clientes/buscar${qs({ q, limit })}`),
  crear: (payload) => apiFetch("/clientes", { method: "POST", body: payload }),
  actualizar: (id, payload) => apiFetch(`/clientes/${id}`, { method: "PATCH", body: payload }),
  eliminar: (id) => apiFetch(`/clientes/${id}`, { method: "DELETE" }),
  activarPortal: (id, password) =>
    apiFetch(`/clientes/${id}/portal`, { method: "POST", body: { password } }),
  comunicaciones: (params = {}) => apiFetch(`/clientes/comunicaciones${qs(params)}`),
  registrarComunicacion: (payload) =>
    apiFetch("/clientes/comunicaciones", { method: "POST", body: payload }),
};
