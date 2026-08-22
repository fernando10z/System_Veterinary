import { apiFetch, qs } from "../../../shared/api/client.js";

export const mascotasApi = {
  listar: (params = {}) => apiFetch(`/mascotas${qs(params)}`),
  obtener: (id) => apiFetch(`/mascotas/${id}`),
  /** Línea de tiempo clínica unificada del paciente. */
  historia: (id, params = {}) => apiFetch(`/mascotas/${id}/historia${qs(params)}`),
  carneVacunas: (id) => apiFetch(`/mascotas/${id}/vacunas`),
  documentos: (id) => apiFetch(`/mascotas/${id}/documentos`),
  crear: (payload) => apiFetch("/mascotas", { method: "POST", body: payload }),
  actualizar: (id, payload) => apiFetch(`/mascotas/${id}`, { method: "PATCH", body: payload }),
  eliminar: (id) => apiFetch(`/mascotas/${id}`, { method: "DELETE" }),
  extraviadas: (todas = false) => apiFetch(`/mascotas/extraviadas${qs({ todas })}`),
  reportarExtravio: (payload) => apiFetch("/mascotas/extravios", { method: "POST", body: payload }),
  marcarEncontrada: (id) => apiFetch(`/mascotas/extravios/${id}/encontrada`, { method: "PATCH" }),
};
