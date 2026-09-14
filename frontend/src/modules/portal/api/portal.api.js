import { API_BASE_URL, PORTAL_TOKEN_KEY, PORTAL_CLIENTE_KEY } from "../../../shared/config/api.config.js";

/**
 * Cliente HTTP del portal del propietario. Vive aparte del `apiFetch` del
 * backoffice porque usa su propio token (type=portal) y no debe compartir ni
 * el almacenamiento ni el refresh del staff.
 */
async function portalFetch(path, { method = "GET", body } = {}) {
  const token = localStorage.getItem(PORTAL_TOKEN_KEY);
  const res = await fetch(`${API_BASE_URL}${path}`, {
    method,
    headers: {
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  let payload = null;
  try {
    payload = await res.json();
  } catch {
    payload = null;
  }

  if (res.status === 401) {
    localStorage.removeItem(PORTAL_TOKEN_KEY);
    localStorage.removeItem(PORTAL_CLIENTE_KEY);
    if (!window.location.pathname.startsWith("/portal/login")) {
      window.location.href = "/portal/login";
    }
    throw new Error("Sesión expirada");
  }

  if (!res.ok || payload?.ok === false) {
    const err = new Error(payload?.error?.message ?? `HTTP ${res.status}`);
    err.code = payload?.error?.code;
    throw err;
  }
  return payload;
}

export const portalApi = {
  async login(documento, password) {
    const r = await portalFetch("/auth/portal/login", {
      method: "POST",
      body: { documento, password },
    });
    localStorage.setItem(PORTAL_TOKEN_KEY, r.data.access_token);
    localStorage.setItem(PORTAL_CLIENTE_KEY, JSON.stringify(r.data.cliente));
    return r.data;
  },
  logout() {
    localStorage.removeItem(PORTAL_TOKEN_KEY);
    localStorage.removeItem(PORTAL_CLIENTE_KEY);
  },
  cliente() {
    try {
      return JSON.parse(localStorage.getItem(PORTAL_CLIENTE_KEY) || "null");
    } catch {
      return null;
    }
  },
  autenticado: () => !!localStorage.getItem(PORTAL_TOKEN_KEY),

  misMascotas: () => portalFetch("/portal/mis-mascotas"),
  misCitas: (pasadas = true) => portalFetch(`/portal/mis-citas?pasadas=${pasadas}`),
  historial: (mascotaId) => portalFetch(`/portal/mascotas/${mascotaId}/historial`),
  misComprobantes: () => portalFetch("/portal/mis-comprobantes"),
  solicitarCita: (payload) => portalFetch("/portal/citas", { method: "POST", body: payload }),
  cambiarPassword: (password_actual, password_nuevo) =>
    portalFetch("/portal/cambiar-password", {
      method: "POST",
      body: { password_actual, password_nuevo },
    }),
};
