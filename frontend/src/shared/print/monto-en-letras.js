/**
 * El importe en letras que todo comprobante peruano lleva impreso
 * ("SON: CIENTO VEINTE CON 00/100 SOLES").
 *
 * No es decorativo: SUNAT lo exige en la representación impresa, y es lo que
 * prevalece si el número quedó ilegible.
 */

const UNIDADES = [
  "", "UNO", "DOS", "TRES", "CUATRO", "CINCO", "SEIS", "SIETE", "OCHO", "NUEVE",
  "DIEZ", "ONCE", "DOCE", "TRECE", "CATORCE", "QUINCE", "DIECISÉIS", "DIECISIETE",
  "DIECIOCHO", "DIECINUEVE", "VEINTE",
];

const DECENAS = [
  "", "", "VEINTI", "TREINTA", "CUARENTA", "CINCUENTA",
  "SESENTA", "SETENTA", "OCHENTA", "NOVENTA",
];

const CENTENAS = [
  "", "CIENTO", "DOSCIENTOS", "TRESCIENTOS", "CUATROCIENTOS", "QUINIENTOS",
  "SEISCIENTOS", "SETECIENTOS", "OCHOCIENTOS", "NOVECIENTOS",
];

/**
 * Convierte 0–999 a letras.
 *
 * `apocope` recorta el "uno" final a "un", que es lo que corresponde cuando
 * detrás viene un sustantivo masculino: VEINTIÚN MIL, TREINTA Y UN SOLES.
 * Decir "veintiuno mil" es incorrecto, y en un documento tributario el importe
 * en letras es el que prevalece.
 */
function centenasEnLetras(n, apocope = false) {
  if (n === 0) return "";
  if (n === 100) return "CIEN";

  const c = Math.floor(n / 100);
  const resto = n % 100;
  const partes = [];

  if (c > 0) partes.push(CENTENAS[c]);

  if (resto > 0) {
    if (resto <= 20) {
      partes.push(apocope && resto === 1 ? "UN" : UNIDADES[resto]);
    } else {
      const d = Math.floor(resto / 10);
      const u = resto % 10;
      const unidad = apocope && u === 1 ? "ÚN" : UNIDADES[u];
      // "VEINTIUNO" va pegado; de treinta en adelante lleva "Y".
      if (d === 2) {
        partes.push(DECENAS[2] + (u ? unidad : "NTE"));
      } else {
        partes.push(DECENAS[d] + (u ? " Y " + (apocope && u === 1 ? "UN" : UNIDADES[u]) : ""));
      }
    }
  }

  return partes.join(" ");
}

/** Convierte la parte entera del monto a letras. */
function enteroEnLetras(n) {
  if (n === 0) return "CERO";

  const millones = Math.floor(n / 1_000_000);
  const miles = Math.floor((n % 1_000_000) / 1000);
  const resto = n % 1000;
  const partes = [];

  if (millones > 0) {
    partes.push(
      millones === 1 ? "UN MILLÓN" : `${centenasEnLetras(millones, true)} MILLONES`,
    );
  }
  if (miles > 0) {
    // "UN MIL" no se dice: es "MIL".
    partes.push(miles === 1 ? "MIL" : `${centenasEnLetras(miles, true)} MIL`);
  }
  if (resto > 0) {
    // Detrás viene la moneda (SOLES, DÓLARES): también apocopa.
    partes.push(centenasEnLetras(resto, true));
  }

  return partes.join(" ");
}

const MONEDAS = {
  PEN: "SOLES",
  USD: "DÓLARES AMERICANOS",
};

/**
 * @param {number|string} monto
 * @param {"PEN"|"USD"} moneda
 * @returns {string} p. ej. "CIENTO VEINTE CON 50/100 SOLES"
 */
export function montoEnLetras(monto, moneda = "PEN") {
  const n = Number(monto);
  if (!Number.isFinite(n)) return "";

  // Se redondea antes de partir: 120.999 son 121.00, no "120 CON 99/100".
  const centavosTotales = Math.round(Math.abs(n) * 100);
  const entero = Math.floor(centavosTotales / 100);
  const centavos = centavosTotales % 100;

  const letras = enteroEnLetras(entero);
  const signo = n < 0 ? "MENOS " : "";

  return `${signo}${letras} CON ${String(centavos).padStart(2, "0")}/100 ${
    MONEDAS[moneda] ?? MONEDAS.PEN
  }`;
}
