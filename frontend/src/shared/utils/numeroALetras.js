// Importe en letras para documentos impresos (proforma, comprobante).
// Español, cubre hasta millones, que es de sobra para los importes del ERP.

export function numeroALetras(num) {
  const n = Math.floor(Math.abs(num));
  const dec = Math.round((Math.abs(num) - n) * 100);
  const signo = num < 0 ? "MENOS " : "";
  return `${signo}${enteroALetras(n)} Y ${String(dec).padStart(2, "0")}/100`;
}

/** `SON MIL DOSCIENTOS Y 00/100 SOLES` — la línea que va sobre los totales. */
export function importeEnLetras(monto, moneda) {
  const nombre = moneda === "USD" ? "DÓLARES AMERICANOS" : "SOLES";
  return `SON ${numeroALetras(Number(monto) || 0).toUpperCase()} ${nombre}`;
}

const UNI = ["", "UNO", "DOS", "TRES", "CUATRO", "CINCO", "SEIS", "SIETE", "OCHO", "NUEVE"];
const DIEZ = ["DIEZ", "ONCE", "DOCE", "TRECE", "CATORCE", "QUINCE", "DIECISÉIS", "DIECISIETE", "DIECIOCHO", "DIECINUEVE"];
const DEC = ["", "", "VEINTE", "TREINTA", "CUARENTA", "CINCUENTA", "SESENTA", "SETENTA", "OCHENTA", "NOVENTA"];
const CEN = ["", "CIENTO", "DOSCIENTOS", "TRESCIENTOS", "CUATROCIENTOS", "QUINIENTOS", "SEISCIENTOS", "SETECIENTOS", "OCHOCIENTOS", "NOVECIENTOS"];

function bajo1000(x) {
  if (x === 0) return "";
  if (x === 100) return "CIEN";
  const cen = Math.floor(x / 100);
  const r = x % 100;
  let txt = cen > 0 ? CEN[cen] : "";
  if (r > 0) {
    if (txt) txt += " ";
    if (r < 10) txt += UNI[r];
    else if (r < 20) txt += DIEZ[r - 10];
    else {
      const d = Math.floor(r / 10);
      const u = r % 10;
      if (d === 2 && u > 0) txt += "VEINTI" + UNI[u];
      else if (u === 0) txt += DEC[d];
      else txt += DEC[d] + " Y " + UNI[u];
    }
  }
  return txt;
}

function enteroALetras(n) {
  if (n === 0) return "CERO";
  if (n < 1000) return bajo1000(n);

  if (n < 1000000) {
    const miles = Math.floor(n / 1000);
    const resto = n % 1000;
    const txt = miles === 1 ? "MIL" : `${bajo1000(miles)} MIL`;
    return resto > 0 ? `${txt} ${bajo1000(resto)}` : txt;
  }

  const millones = Math.floor(n / 1000000);
  const resto = n % 1000000;
  const txt = millones === 1 ? "UN MILLÓN" : `${enteroALetras(millones)} MILLONES`;
  return resto > 0 ? `${txt} ${enteroALetras(resto)}` : txt;
}
