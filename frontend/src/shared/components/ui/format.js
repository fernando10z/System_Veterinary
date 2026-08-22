export const fmtSoles = (n, decimals = 2) =>
  "S/ " + (Number(n) || 0).toLocaleString("es-PE", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  });

export const fmtNum = (n, decimals = 0) =>
  (Number(n) || 0).toLocaleString("es-PE", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  });

// Nombre corto de un usuario: solo el primer nombre y el apellido paterno.
// Acepta un objeto con { nombres, apellido_paterno } y cae a email/—.
export const fmtNombreCorto = (u) => {
  if (!u) return "—";
  const primerNombre = String(u.nombres || "").trim().split(/\s+/)[0] || "";
  const apPaterno = String(u.apellido_paterno || "").trim();
  return [primerNombre, apPaterno].filter(Boolean).join(" ") || u.email || "—";
};

export const fmtDate = (d) => {
  if (!d) return "—";
  if (typeof d === "string" && /^\d{2}\/\d{2}\/\d{4}/.test(d)) return d;
  // Un DATE ("2026-06-15") lo interpreta new Date() como medianoche UTC y al
  // mostrarlo en hora de Lima (UTC-5) retrocede un día. Para fechas sin hora,
  // construimos la fecha en hora local.
  const m = typeof d === "string" && d.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  const date = m
    ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
    : new Date(d);
  if (Number.isNaN(date.getTime())) return d;
  return date.toLocaleDateString("es-PE", { day: "2-digit", month: "2-digit", year: "numeric" });
};

/** Fecha + hora corta en formato local (es-PE). */
export const fmtFechaHora = (d) => {
  if (!d) return "—";
  const date = new Date(d);
  if (Number.isNaN(date.getTime())) return String(d);
  return date.toLocaleString("es-PE", {
    day: "2-digit", month: "2-digit", year: "numeric",
    hour: "2-digit", minute: "2-digit",
  });
};

/** Solo la hora ("14:30"), para las tarjetas de agenda. */
export const fmtHora = (d) => {
  if (!d) return "—";
  const date = new Date(d);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleTimeString("es-PE", { hour: "2-digit", minute: "2-digit" });
};

/** "hace 3 días" / "en 2 semanas": para vencimientos y últimas visitas. */
export const fmtRelativo = (d) => {
  if (!d) return "—";
  const date = new Date(d);
  if (Number.isNaN(date.getTime())) return "—";
  const dias = Math.round((date - new Date()) / 86400000);
  const rtf = new Intl.RelativeTimeFormat("es", { numeric: "auto" });
  if (Math.abs(dias) < 1) return "hoy";
  if (Math.abs(dias) < 30) return rtf.format(dias, "day");
  if (Math.abs(dias) < 365) return rtf.format(Math.round(dias / 30), "month");
  return rtf.format(Math.round(dias / 365), "year");
};

/** Primera letra en mayúscula; los enums de la BD llegan en minúscula. */
export const capitalizar = (s) =>
  !s ? "—" : String(s).charAt(0).toUpperCase() + String(s).slice(1).replace(/_/g, " ");

/** Iniciales para el avatar del propietario o del profesional. */
export const iniciales = (nombre = "") => {
  const p = String(nombre).trim().split(/\s+/).filter(Boolean);
  if (!p.length) return "?";
  if (p.length === 1) return p[0].slice(0, 2).toUpperCase();
  return (p[0][0] + p[p.length - 1][0]).toUpperCase();
};
