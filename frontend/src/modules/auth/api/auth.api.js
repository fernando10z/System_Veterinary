import { apiFetch } from "../../../shared/api/client.js";

export const authApi = {
  perfil: () => apiFetch("/auth/perfil"),
  cambiarPassword: (password_actual, password_nuevo) =>
    apiFetch("/auth/cambiar-password", {
      method: "POST",
      body: { password_actual, password_nuevo },
    }),
  solicitarReset: (email) =>
    apiFetch("/auth/solicitar-reset", { method: "POST", body: { email } }),
  resetPassword: (token, password_nuevo) =>
    apiFetch("/auth/reset-password", { method: "POST", body: { token, password_nuevo } }),
};
