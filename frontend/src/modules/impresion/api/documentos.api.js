import { apiFetch, qs } from "../../../shared/api/client.js";

export const documentosApi = {
  receta: (consultaId) => apiFetch(`/documentos/receta/${consultaId}`),
  carneVacunacion: (mascotaId) => apiFetch(`/documentos/carne-vacunacion/${mascotaId}`),
  consentimiento: (cirugiaId) => apiFetch(`/documentos/consentimiento/${cirugiaId}`),
  altaHospitalaria: (hospId) => apiFetch(`/documentos/alta-hospitalaria/${hospId}`),
  historiaClinica: (mascotaId) => apiFetch(`/documentos/historia-clinica/${mascotaId}`),
  certificadoSalud: (mascotaId, params = {}) =>
    apiFetch(`/documentos/certificado-salud/${mascotaId}${qs(params)}`),
};
