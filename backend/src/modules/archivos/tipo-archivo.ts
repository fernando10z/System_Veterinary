import { Readable } from "stream";

/**
 * Qué se acepta como archivo clínico y cómo se reconoce por su contenido.
 *
 * El Content-Type lo escribe el cliente: por sí solo no prueba nada. Un .html
 * con `type=image/png` pasaba la lista blanca, quedaba en el almacén y, al
 * abrirlo desde un enlace, el navegador lo interpretaba. Aquí se comprueban los
 * primeros bytes del archivo contra la firma del tipo declarado.
 */

/** Bytes que hacen falta para reconocer cualquiera de los tipos (DICOM: 132). */
export const BYTES_CABECERA = 132;

export const MAX_BYTES = 50 * 1024 * 1024;

type Firma = (b: Buffer) => boolean;

const empiezaCon = (b: Buffer, ...bytes: number[]) =>
  b.length >= bytes.length && bytes.every((v, i) => b[i] === v);
const ascii = (b: Buffer, desde: number, texto: string) =>
  b.length >= desde + texto.length && b.toString("latin1", desde, desde + texto.length) === texto;

const FIRMAS = {
  pdf: (b: Buffer) => ascii(b, 0, "%PDF-"),
  png: (b: Buffer) => empiezaCon(b, 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a),
  jpeg: (b: Buffer) => empiezaCon(b, 0xff, 0xd8, 0xff),
  webp: (b: Buffer) => ascii(b, 0, "RIFF") && ascii(b, 8, "WEBP"),
  gif: (b: Buffer) => ascii(b, 0, "GIF87a") || ascii(b, 0, "GIF89a"),
  bmp: (b: Buffer) => ascii(b, 0, "BM"),
  tiff: (b: Buffer) => empiezaCon(b, 0x49, 0x49, 0x2a, 0x00) || empiezaCon(b, 0x4d, 0x4d, 0x00, 0x2a),
  // DICOM Part 10: 128 bytes de preámbulo y la marca "DICM".
  dicom: (b: Buffer) => ascii(b, 128, "DICM"),
  // docx/xlsx son ZIP; distinguir uno de otro exigiría abrirlo, y el riesgo
  // que se busca cerrar (contenido ejecutable por el navegador) ya queda fuera.
  zip: (b: Buffer) => empiezaCon(b, 0x50, 0x4b, 0x03, 0x04),
  texto: (b: Buffer) => esTextoPlano(b),
} satisfies Record<string, Firma>;

/**
 * Lista blanca: MIME declarado → firma que debe cumplir el contenido y
 * extensiones con que se reconoce. `directa` marca los que se pueden subir con
 * URL prefirmada (sin pasar por el backend): solo binarios con firma fuerte,
 * porque ese camino no permite mirar el contenido.
 */
export const TIPOS: Record<string, { firma: Firma; ext: string[]; directa: boolean }> = {
  "image/jpeg": { firma: FIRMAS.jpeg, ext: ["jpg", "jpeg"], directa: true },
  "image/png": { firma: FIRMAS.png, ext: ["png"], directa: true },
  "image/webp": { firma: FIRMAS.webp, ext: ["webp"], directa: true },
  "image/gif": { firma: FIRMAS.gif, ext: ["gif"], directa: false },
  "image/bmp": { firma: FIRMAS.bmp, ext: ["bmp"], directa: false },
  "image/tiff": { firma: FIRMAS.tiff, ext: ["tif", "tiff"], directa: true },
  "application/pdf": { firma: FIRMAS.pdf, ext: ["pdf"], directa: true },
  "application/dicom": { firma: FIRMAS.dicom, ext: ["dcm", "dicom"], directa: true },
  "text/plain": { firma: FIRMAS.texto, ext: ["txt"], directa: false },
  "text/csv": { firma: FIRMAS.texto, ext: ["csv"], directa: false },
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": {
    firma: FIRMAS.zip, ext: ["docx"], directa: false,
  },
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": {
    firma: FIRMAS.zip, ext: ["xlsx"], directa: false,
  },
};

/** "Image/PNG; charset=x" → "image/png". */
export function normalizarMime(mime?: string | null): string {
  return (mime ?? "").split(";")[0].trim().toLowerCase();
}

export function mimePermitido(mime?: string | null): boolean {
  return normalizarMime(mime) in TIPOS;
}

/** MIME a partir de la extensión del nombre, o null si no es uno admitido. */
export function mimePorExtension(nombre: string): string | null {
  const ext = (nombre.split(".").pop() ?? "").toLowerCase();
  for (const [mime, t] of Object.entries(TIPOS)) if (t.ext.includes(ext)) return mime;
  return null;
}

/** ¿El contenido (sus primeros bytes) corresponde al tipo declarado? */
export function contenidoCoincide(mime: string, cabecera: Buffer): boolean {
  const t = TIPOS[normalizarMime(mime)];
  return !!t && t.firma(cabecera);
}

/**
 * Texto plano de verdad: sin bytes nulos ni de control binarios, y sin nada
 * que un navegador pudiera tomar por HTML o SVG si alguna vez lo sirviera con
 * otro tipo.
 */
function esTextoPlano(b: Buffer): boolean {
  if (b.length === 0) return false;
  for (const byte of b) {
    if (byte === 0) return false;
    if (byte < 0x09 || (byte > 0x0d && byte < 0x20 && byte !== 0x1b)) return false;
  }
  const inicio = b.toString("utf8").trimStart().slice(0, 64).toLowerCase();
  return !/^<(!doctype|html|script|svg|\?xml|body|iframe)/.test(inicio);
}

/** El archivo superó el tamaño máximo mientras se leía. */
export class ArchivoDemasiadoGrande extends Error {
  constructor() {
    super("El archivo supera el tamaño máximo");
  }
}

/**
 * Lee los primeros `n` bytes de un stream sin cargar el resto en memoria.
 * Devuelve esa cabecera y un stream nuevo que emite el archivo COMPLETO
 * (cabecera incluida), contando bytes: si pasa de `maxBytes` falla con
 * ArchivoDemasiadoGrande y la subida a MinIO se aborta.
 */
export async function leerCabecera(
  origen: AsyncIterable<Buffer | string>,
  n = BYTES_CABECERA,
  maxBytes = MAX_BYTES,
): Promise<{ cabecera: Buffer; cuerpo: Readable; bytes: () => number }> {
  const it = origen[Symbol.asyncIterator]();
  const trozos: Buffer[] = [];
  let leidos = 0;
  let terminado = false;
  while (leidos < n) {
    const r = await it.next();
    if (r.done) { terminado = true; break; }
    const b = Buffer.isBuffer(r.value) ? r.value : Buffer.from(r.value);
    trozos.push(b);
    leidos += b.length;
  }
  const inicio = Buffer.concat(trozos);
  if (inicio.length > maxBytes) throw new ArchivoDemasiadoGrande();
  let total = inicio.length;

  async function* todo(): AsyncGenerator<Buffer> {
    if (inicio.length) yield inicio;
    if (terminado) return;
    for (;;) {
      const r = await it.next();
      if (r.done) return;
      const b = Buffer.isBuffer(r.value) ? r.value : Buffer.from(r.value);
      total += b.length;
      if (total > maxBytes) throw new ArchivoDemasiadoGrande();
      yield b;
    }
  }

  return { cabecera: inicio.subarray(0, n), cuerpo: Readable.from(todo()), bytes: () => total };
}
