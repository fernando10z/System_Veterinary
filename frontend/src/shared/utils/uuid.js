/**
 * UUID v4 para las claves de idempotencia (cobros, emisión de comprobantes).
 *
 * crypto.randomUUID solo existe en contextos seguros (https o localhost): en
 * la red local de la clínica (http://192.168.x.x) no está. getRandomValues sí
 * está disponible en cualquier contexto.
 */
export function uuid() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    try { return crypto.randomUUID(); } catch { /* contexto no seguro */ }
  }
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
