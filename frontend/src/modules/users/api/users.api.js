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
  cambiarRol: (id, rol_id, empresa_id) =>
    apiFetch(`/users/${id}/rol`, { method: "PATCH", body: { rol_id, empresa_id } }),
  resetPassword: (id, password_temp) =>
    apiFetch(`/users/${id}/reset-password`, { method: "POST", body: { password_temp } }),
  eliminar: (id) => apiFetch(`/users/${id}`, { method: "DELETE" }),
};
