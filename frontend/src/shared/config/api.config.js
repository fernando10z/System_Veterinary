// En desarrollo el backend corre aparte en :3100; en un build de producción el
// frontend se sirve detrás del mismo dominio (nginx hace de proxy a /api), así
// que el fallback es relativo y funciona en cualquier host o IP de la clínica.
export const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL || (import.meta.env.PROD ? "/api" : "http://localhost:3100/api");

// Claves con prefijo propio: si alguien abre este ERP y el de maquinaria en el
// mismo navegador, las sesiones no se pisan.
export const ACCESS_TOKEN_KEY = "vet_access_token";
export const REFRESH_TOKEN_KEY = "vet_refresh_token";
export const USER_KEY = "vet_user";
export const PERMS_KEY = "vet_permisos";

// Portal del propietario: token independiente del backoffice.
export const PORTAL_TOKEN_KEY = "vet_portal_token";
export const PORTAL_CLIENTE_KEY = "vet_portal_cliente";
