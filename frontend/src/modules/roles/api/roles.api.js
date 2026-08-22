import { apiFetch } from "../../../shared/api/client.js";

export const rolesApi = {
  listar: () => apiFetch("/roles"),
  /** Permisos agrupados por módulo, listos para la matriz de la UI. */
  permisos: () => apiFetch("/roles/permisos"),
  crear: (payload) => apiFetch("/roles", { method: "POST", body: payload }),
  setPermisos: (id, codigos) =>
    apiFetch(`/roles/${id}/permisos`, { method: "PUT", body: { codigos } }),
  eliminar: (id) => apiFetch(`/roles/${id}`, { method: "DELETE" }),
};
