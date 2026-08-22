import { apiFetch, qs } from "../../../shared/api/client.js";

export const usersApi = {
  listar: (params = {}) => apiFetch(`/users${qs(params)}`),
  obtener: (id) => apiFetch(`/users/${id}`),
  /** Atajo para los selects de agenda e historia clínica. */
  veterinarios: () => apiFetch("/users/veterinarios"),
  crear: (payload) => apiFetch("/users", { method: "POST", body: payload }),
  actualizar: (id, payload) => apiFetch(`/users/${id}`, { method: "PATCH", body: payload }),
  cambiarEstado: (id, estado) =>
    apiFetch(`/users/${id}/estado`, { method: "PATCH", body: { estado } }),
  cambiarRol: (id, rolId, empresaId) =>
    apiFetch(`/users/${id}/rol`, { method: "PATCH", body: { rolId, empresaId } }),
  resetPassword: (id, passwordTemp) =>
    apiFetch(`/users/${id}/reset-password`, { method: "POST", body: { passwordTemp } }),
  eliminar: (id) => apiFetch(`/users/${id}`, { method: "DELETE" }),
};
