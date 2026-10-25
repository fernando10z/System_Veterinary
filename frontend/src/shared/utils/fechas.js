/**
 * Fechas en hora LOCAL (Lima, UTC-5).
 *
 * `new Date().toISOString().slice(0, 10)` devuelve la fecha en UTC: después de
 * las 19:00 en Lima el sistema cree que ya es mañana (la agenda salta de día,
 * la boleta sale con fecha futura, la vacuna se registra al día siguiente).
 * Todo cálculo de "fecha sin hora" del frontend pasa por aquí.
 */

const pad = (n) => String(n).padStart(2, "0");

/** Date → "YYYY-MM-DD" en hora local. */
export function isoLocal(d = new Date()) {
  const date = d instanceof Date ? d : parseFecha(d);
  if (!date || Number.isNaN(date.getTime())) return "";
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** Hoy como "YYYY-MM-DD" local. */
export const hoyISO = () => isoLocal(new Date());

/** Primer día del mes (del mes de `d`, por defecto el actual). */
export function inicioMesISO(d = new Date()) {
  return isoLocal(new Date(d.getFullYear(), d.getMonth(), 1));
}

/**
 * Interpreta "YYYY-MM-DD" como medianoche LOCAL (new Date("2026-06-15") la
 * toma como UTC y en Lima retrocede un día). Otros formatos van a new Date().
 */
export function parseFecha(v) {
  if (v instanceof Date) return new Date(v.getTime());
  if (!v) return null;
  const m = typeof v === "string" && v.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Suma (o resta) días a una fecha "YYYY-MM-DD" y devuelve "YYYY-MM-DD". */
export function sumarDias(iso, dias) {
  const d = parseFecha(iso) || new Date();
  return isoLocal(new Date(d.getFullYear(), d.getMonth(), d.getDate() + Number(dias || 0)));
}

/** Suma meses de calendario (31/01 + 1 mes = 28 o 29/02, no 03/03). */
export function sumarMeses(iso, meses) {
  const d = parseFecha(iso) || new Date();
  const objetivo = new Date(d.getFullYear(), d.getMonth() + Number(meses || 0), 1);
  const ultimo = new Date(objetivo.getFullYear(), objetivo.getMonth() + 1, 0).getDate();
  objetivo.setDate(Math.min(d.getDate(), ultimo));
  return isoLocal(objetivo);
}

/** Valor para <input type="datetime-local">: "YYYY-MM-DDTHH:mm" en hora local. */
export function datetimeLocal(v = new Date()) {
  const d = parseFecha(v);
  if (!d) return "";
  return `${isoLocal(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** "YYYY-MM-DDTHH:mm" (local) → ISO con zona, para enviar a la API. */
export function datetimeLocalAISO(v) {
  if (!v) return null;
  const d = new Date(v); // sin zona => el navegador la interpreta como local
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/** Fecha para mostrar ("15/06/2026"), sin desfase de zona. */
export function fmtFechaLocal(v) {
  const d = parseFecha(v);
  if (!d) return "—";
  return d.toLocaleDateString("es-PE", { day: "2-digit", month: "2-digit", year: "numeric" });
}
