export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || "http://localhost:3100/api";

// Claves con prefijo propio: si alguien abre este ERP y el de maquinaria en el
// mismo navegador, las sesiones no se pisan.
export const ACCESS_TOKEN_KEY = "vet_access_token";
export const REFRESH_TOKEN_KEY = "vet_refresh_token";
export const USER_KEY = "vet_user";

// Portal del propietario: token independiente del backoffice.
export const PORTAL_TOKEN_KEY = "vet_portal_token";
export const PORTAL_CLIENTE_KEY = "vet_portal_cliente";
