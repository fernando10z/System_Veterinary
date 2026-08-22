import { API_BASE_URL, ACCESS_TOKEN_KEY, REFRESH_TOKEN_KEY } from "../config/api.config.js";

function getAccess() {
  return localStorage.getItem(ACCESS_TOKEN_KEY);
}
function getRefresh() {
  return localStorage.getItem(REFRESH_TOKEN_KEY);
}
function setTokens(access, refresh) {
  if (access) localStorage.setItem(ACCESS_TOKEN_KEY, access);
  if (refresh) localStorage.setItem(REFRESH_TOKEN_KEY, refresh);
}
function clearTokens() {
  localStorage.removeItem(ACCESS_TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
}

let refreshInFlight = null;

async function tryRefresh() {
  if (refreshInFlight) return refreshInFlight;
  const refresh = getRefresh();
  if (!refresh) return null;
  refreshInFlight = (async () => {
    try {
      const r = await fetch(`${API_BASE_URL}/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refreshToken: refresh }),
      });
      const j = await r.json();
      if (!r.ok || !j.ok) return null;
      setTokens(j.data.accessToken, j.data.refreshToken);
      return j.data.accessToken;
    } catch {
      return null;
    } finally {
      refreshInFlight = null;
    }
  })();
  return refreshInFlight;
}

export async function apiFetch(path, { method = "GET", body, headers = {}, _retry = false } = {}) {
  const url = path.startsWith("http") ? path : `${API_BASE_URL}${path}`;
  const token = getAccess();
  const finalHeaders = {
    ...(body && !(body instanceof FormData) ? { "Content-Type": "application/json" } : {}),
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...headers,
  };
  const res = await fetch(url, {
    method,
    headers: finalHeaders,
    body: body instanceof FormData ? body : body ? JSON.stringify(body) : undefined,
  });

  if (res.status === 401 && !_retry) {
    const newToken = await tryRefresh();
    if (newToken) {
      return apiFetch(path, { method, body, headers, _retry: true });
    }
    clearTokens();
    if (typeof window !== "undefined" && !window.location.pathname.endsWith("/login")) {
      window.location.href = "/login";
    }
    throw new Error("No autorizado");
  }

  let payload = null;
  try {
    payload = await res.json();
  } catch {
    payload = null;
  }

  if (!res.ok || (payload && payload.ok === false)) {
    const err = new Error(payload?.error?.message ?? `HTTP ${res.status}`);
    err.code = payload?.error?.code;
    err.status = res.status;
    err.detail = payload?.error?.detail;
    throw err;
  }
  return payload;
}

export const auth = {
  setTokens,
  clearTokens,
  getAccess,
};

/**
 * Trae todas las páginas de un listado paginado por SP ({ data, meta:{ total, pages } }).
 * Los SP topan p_page_size en 100, así que pedir más en una sola llamada no trae más filas:
 * hay que recorrer las páginas. `cap` acota cuántas se piden para que un rango muy amplio
 * no dispare cientos de requests; si se alcanza, `truncado` avisa que faltan filas.
 */
export async function fetchAllPages(listar, params = {}, { pageSize = 100, cap = 20 } = {}) {
  const first = await listar({ ...params, page: 1, pageSize });
  const rows = [...(first.data ?? [])];
  const pages = first.meta?.pages ?? 1;
  const ultima = Math.min(pages, cap);

  if (ultima > 1) {
    const resto = await Promise.all(
      Array.from({ length: ultima - 1 }, (_, i) =>
        listar({ ...params, page: i + 2, pageSize }),
      ),
    );
    resto.forEach((r) => rows.push(...(r.data ?? [])));
  }

  return { rows, total: first.meta?.total ?? rows.length, truncado: pages > cap };
}

/** Helper para armar query strings ignorando valores vacíos. */
export function qs(params = {}) {
  const q = new URLSearchParams();
  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== "") q.set(k, String(v));
  });
  const s = q.toString();
  return s ? `?${s}` : "";
}
