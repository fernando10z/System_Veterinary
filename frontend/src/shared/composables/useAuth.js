import { reactive, computed } from "vue";
import { apiFetch, auth } from "../api/client.js";
import { ACCESS_TOKEN_KEY, USER_KEY } from "../config/api.config.js";

const PERMS_KEY = "vet_permisos";

function loadStoredUser() {
  try {
    const s = localStorage.getItem(USER_KEY);
    return s ? JSON.parse(s) : null;
  } catch {
    return null;
  }
}

function loadStoredPerms() {
  try {
    const s = localStorage.getItem(PERMS_KEY);
    return s ? JSON.parse(s) : [];
  } catch {
    return [];
  }
}

const state = reactive({
  isAuthenticated: !!localStorage.getItem(ACCESS_TOKEN_KEY),
  user: loadStoredUser(),
  permisos: loadStoredPerms(),
});

function persistUser(user) {
  if (user) localStorage.setItem(USER_KEY, JSON.stringify(user));
  else localStorage.removeItem(USER_KEY);
}

function persistPerms(perms) {
  if (perms) localStorage.setItem(PERMS_KEY, JSON.stringify(perms));
  else localStorage.removeItem(PERMS_KEY);
}

function decorateUser(raw, rol) {
  if (!raw) return null;
  const nombres = (raw.nombres || "").trim();
  // En la UI mostramos solo el primer nombre y el apellido paterno.
  const primerNombre = nombres.split(/\s+/)[0] || "";
  const apPaterno = (raw.apellido_paterno || "").trim();
  const nombre = [primerNombre, apPaterno].filter(Boolean).join(" ") || raw.email;
  const iniciales = ((primerNombre[0] || "") + (apPaterno[0] || "")).toUpperCase() || "?";
  const rolNombre = rol?.nombre ?? null;
  return {
    ...raw,
    nombre,
    iniciales,
    rol_codigo: rol?.codigo ?? null,
    rol_nombre: rolNombre,
    cargo: raw.is_super_admin ? "Super Administrador" : rolNombre || "Usuario",
  };
}

async function login(email, password) {
  try {
    const res = await apiFetch("/auth/login", {
      method: "POST",
      body: { email, password },
    });
    auth.setTokens(res.data.access_token, res.data.refresh_token);
    const user = decorateUser(res.data.user, res.data.rol);
    const permisos = Array.isArray(res.data.permisos) ? res.data.permisos : [];
    state.user = user;
    state.permisos = permisos;
    state.isAuthenticated = true;
    persistUser(user);
    persistPerms(permisos);
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err.message || "Credenciales inválidas" };
  }
}

function logout() {
  auth.clearTokens();
  persistUser(null);
  persistPerms(null);
  state.user = null;
  state.permisos = [];
  state.isAuthenticated = false;
}

function hasPermission(code) {
  if (!code) return true;
  if (state.user?.is_super_admin) return true;
  return state.permisos.includes(code);
}

function hasAnyPermission(codes) {
  return codes.some((c) => hasPermission(c));
}

function hasRole(code) {
  if (state.user?.is_super_admin) return true;
  return state.user?.rol_codigo === code;
}

function hasAnyRole(codes) {
  return codes.some((c) => hasRole(c));
}

export function useAuth() {
  return {
    isAuthenticated: computed(() => state.isAuthenticated),
    user: computed(() => state.user),
    permisos: computed(() => state.permisos),
    isSuperAdmin: computed(() => !!state.user?.is_super_admin),
    login,
    logout,
    hasPermission,
    hasAnyPermission,
    hasRole,
    hasAnyRole,
  };
}
