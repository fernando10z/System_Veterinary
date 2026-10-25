/**
 * Validaciones de formularios para datos peruanos. Devuelven "" si el valor es
 * válido (o está vacío y no es obligatorio) y el mensaje de error si no.
 */

/** Documento de identidad según su tipo (DNI, RUC, CE, PASAPORTE). */
export function validarDocumento(tipo, numero) {
  const n = String(numero ?? "").trim();
  if (!n) return "Ingresa el número de documento.";
  switch (tipo) {
    case "DNI":
      return /^\d{8}$/.test(n) ? "" : "El DNI tiene exactamente 8 dígitos.";
    case "RUC":
      if (!/^\d{11}$/.test(n)) return "El RUC tiene exactamente 11 dígitos.";
      return /^(10|15|17|20)/.test(n) ? "" : "El RUC debe empezar con 10, 15, 17 o 20.";
    case "CE":
      return /^[A-Za-z0-9]{1,12}$/.test(n) ? "" : "El carné de extranjería tiene hasta 12 letras o números.";
    case "PASAPORTE":
      return /^[A-Za-z0-9]{5,20}$/.test(n) ? "" : "Pasaporte: entre 5 y 20 letras o números.";
    default:
      return "";
  }
}

/** Longitud máxima del número según el tipo, para el atributo maxlength. */
export function maxDocumento(tipo) {
  return { DNI: 8, RUC: 11, CE: 12, PASAPORTE: 20 }[tipo] ?? 20;
}

/** Celular peruano: 9 dígitos empezando en 9. Se aceptan espacios y +51. */
export function validarCelular(valor, { obligatorio = false } = {}) {
  const v = String(valor ?? "").replace(/[\s-]/g, "").replace(/^\+?51(?=9\d{8}$)/, "");
  if (!v) return obligatorio ? "Ingresa el celular." : "";
  return /^9\d{8}$/.test(v) ? "" : "El celular tiene 9 dígitos y empieza con 9.";
}

/** Teléfono: celular (9 dígitos, empieza con 9) o fijo (6 a 9 dígitos, con código de ciudad). */
export function validarTelefono(valor) {
  const v = String(valor ?? "").replace(/[\s()-]/g, "").replace(/^\+?51/, "");
  if (!v) return "";
  if (/^9\d{8}$/.test(v)) return "";
  if (/^0?[1-8]\d{5,7}$/.test(v)) return "";
  return "Ingresa un celular de 9 dígitos (empieza con 9) o un fijo con su código.";
}

export function validarCorreo(valor) {
  const v = String(valor ?? "").trim();
  if (!v) return "";
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v) ? "" : "Ingresa un correo válido (nombre@dominio.com).";
}

/** Solo dígitos (para los inputs de DNI/RUC mientras se escribe). */
export const soloDigitos = (v) => String(v ?? "").replace(/\D/g, "");
