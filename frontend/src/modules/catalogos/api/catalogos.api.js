import { apiFetch, qs } from "../../../shared/api/client.js";

export const catalogosApi = {
  especies: (todas = false) => apiFetch(`/catalogos/especies${qs({ todas })}`),
  guardarEspecie: (payload) => apiFetch("/catalogos/especies", { method: "POST", body: payload }),
  guardarRaza: (payload) => apiFetch("/catalogos/razas", { method: "POST", body: payload }),

  servicios: (params = {}) => apiFetch(`/catalogos/servicios${qs(params)}`),
  guardarServicio: (payload) => apiFetch("/catalogos/servicios", { method: "POST", body: payload }),
  eliminarServicio: (id) => apiFetch(`/catalogos/servicios/${id}`, { method: "DELETE" }),

  categorias: (ambito) => apiFetch(`/catalogos/categorias${qs({ ambito })}`),
  guardarCategoria: (payload) => apiFetch("/catalogos/categorias", { method: "POST", body: payload }),

  consultorios: () => apiFetch("/catalogos/consultorios"),
  guardarConsultorio: (payload) =>
    apiFetch("/catalogos/consultorios", { method: "POST", body: payload }),

  horarios: () => apiFetch("/catalogos/horarios"),
  guardarHorarios: (horarios) =>
    apiFetch("/catalogos/horarios", { method: "PUT", body: { horarios } }),

  especializaciones: () => apiFetch("/catalogos/especializaciones"),
  guardarEspecializacion: (payload) =>
    apiFetch("/catalogos/especializaciones", { method: "POST", body: payload }),

  esquemasVacunacion: (especieId) =>
    apiFetch(`/catalogos/esquemas-vacunacion${qs({ especieId })}`),
  guardarEsquema: (payload) =>
    apiFetch("/catalogos/esquemas-vacunacion", { method: "POST", body: payload }),

  clausulas: (tipo) => apiFetch(`/catalogos/clausulas${qs({ tipo })}`),
  guardarClausula: (payload) => apiFetch("/catalogos/clausulas", { method: "POST", body: payload }),
};
