import { apiFetch } from "../../../shared/api/client.js";

export const authApi = {
  perfil: () => apiFetch("/auth/perfil"),
  cambiarPassword: (passwordActual, passwordNuevo) =>
    apiFetch("/auth/cambiar-password", {
      method: "POST",
      body: { passwordActual, passwordNuevo },
    }),
  solicitarReset: (email) =>
    apiFetch("/auth/solicitar-reset", { method: "POST", body: { email } }),
  resetPassword: (token, passwordNuevo) =>
    apiFetch("/auth/reset-password", { method: "POST", body: { token, passwordNuevo } }),
};
