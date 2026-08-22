import { apiFetch, qs } from "../../../shared/api/client.js";

export const reportesApi = {
  ventas: (params = {}) => apiFetch(`/reportes/ventas${qs(params)}`),
  clinico: (params = {}) => apiFetch(`/reportes/clinico${qs(params)}`),
  inventario: (params = {}) => apiFetch(`/reportes/inventario${qs(params)}`),
  ejecutivo: (params = {}) => apiFetch(`/reportes/ejecutivo${qs(params)}`),
};
