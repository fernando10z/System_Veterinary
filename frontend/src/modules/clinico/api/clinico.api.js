import { apiFetch, qs } from "../../../shared/api/client.js";

export const clinicoApi = {
  // consultas
  consultas: (params = {}) => apiFetch(`/clinico/consultas${qs(params)}`),
  consulta: (id) => apiFetch(`/clinico/consultas/${id}`),
  crearConsulta: (payload) => apiFetch("/clinico/consultas", { method: "POST", body: payload }),
  actualizarConsulta: (id, payload) =>
    apiFetch(`/clinico/consultas/${id}`, { method: "PATCH", body: payload }),
  /** Firma la consulta y completa la cita. Exige diagnóstico. */
  cerrarConsulta: (id) => apiFetch(`/clinico/consultas/${id}/cerrar`, { method: "PATCH" }),

  // actos clínicos
  aplicarVacuna: (payload) => apiFetch("/clinico/vacunas", { method: "POST", body: payload }),
  registrarDesparasitacion: (payload) =>
    apiFetch("/clinico/desparasitaciones", { method: "POST", body: payload }),
  registrarTratamiento: (payload) =>
    apiFetch("/clinico/tratamientos", { method: "POST", body: payload }),
  cambiarEstadoTratamiento: (id, estado) =>
    apiFetch(`/clinico/tratamientos/${id}/estado`, { method: "PATCH", body: { estado } }),

  // cirugías
  cirugias: (params = {}) => apiFetch(`/clinico/cirugias${qs(params)}`),
  programarCirugia: (payload) => apiFetch("/clinico/cirugias", { method: "POST", body: payload }),
  resultadoCirugia: (id, payload) =>
    apiFetch(`/clinico/cirugias/${id}/resultado`, { method: "PATCH", body: payload }),

  // hospitalización
  hospitalizaciones: (todas = false) => apiFetch(`/clinico/hospitalizaciones${qs({ todas })}`),
  ingresarHospitalizacion: (payload) =>
    apiFetch("/clinico/hospitalizaciones", { method: "POST", body: payload }),
  registrarEvolucion: (payload) =>
    apiFetch("/clinico/hospitalizaciones/evoluciones", { method: "POST", body: payload }),
  darAlta: (id, payload) =>
    apiFetch(`/clinico/hospitalizaciones/${id}/alta`, { method: "PATCH", body: payload }),

  // exámenes, notas, documentos
  registrarExamen: (payload) => apiFetch("/clinico/examenes", { method: "POST", body: payload }),
  crearNota: (payload) => apiFetch("/clinico/notas", { method: "POST", body: payload }),
  registrarDocumento: (payload) =>
    apiFetch("/clinico/documentos", { method: "POST", body: payload }),

  // facturable
  crearOrdenServicio: (payload) =>
    apiFetch("/clinico/ordenes-servicio", { method: "POST", body: payload }),
  consumirInsumo: (payload) => apiFetch("/clinico/insumos", { method: "POST", body: payload }),
  pendienteFacturar: (clienteId) => apiFetch(`/clinico/pendiente-facturar/${clienteId}`),
};
