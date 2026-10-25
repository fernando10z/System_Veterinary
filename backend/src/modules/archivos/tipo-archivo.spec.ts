import { describe, it, expect } from "vitest";
import { Readable } from "stream";
import {
  ArchivoDemasiadoGrande, contenidoCoincide, leerCabecera, mimePermitido, mimePorExtension,
} from "./tipo-archivo";

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13]);
const JPG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16]);
const PDF = Buffer.from("%PDF-1.7\n%âãÏÓ\n", "latin1");
const WEBP = Buffer.concat([Buffer.from("RIFF"), Buffer.from([1, 2, 3, 4]), Buffer.from("WEBPVP8 ")]);
const DICOM = Buffer.concat([Buffer.alloc(128), Buffer.from("DICM"), Buffer.alloc(8)]);

async function leerTodo(r: Readable): Promise<Buffer> {
  const trozos: Buffer[] = [];
  for await (const t of r) trozos.push(t as Buffer);
  return Buffer.concat(trozos);
}

describe("contenidoCoincide", () => {
  it("reconoce las firmas de los tipos clínicos", () => {
    expect(contenidoCoincide("image/png", PNG)).toBe(true);
    expect(contenidoCoincide("image/jpeg", JPG)).toBe(true);
    expect(contenidoCoincide("application/pdf", PDF)).toBe(true);
    expect(contenidoCoincide("image/webp", WEBP)).toBe(true);
    expect(contenidoCoincide("application/dicom", DICOM)).toBe(true);
  });

  it("rechaza un contenido que no es del tipo declarado", () => {
    expect(contenidoCoincide("image/png", Buffer.from("RADIOGRAFIA DE PRUEBA"))).toBe(false);
    expect(contenidoCoincide("image/png", JPG)).toBe(false);
    expect(contenidoCoincide("application/pdf", PNG)).toBe(false);
    expect(contenidoCoincide("application/dicom", Buffer.alloc(132))).toBe(false);
  });

  it("no deja pasar HTML disfrazado de texto plano", () => {
    expect(contenidoCoincide("text/plain", Buffer.from("Resultado: 12 mg/dl\n"))).toBe(true);
    expect(contenidoCoincide("text/plain", Buffer.from("  <script>alert(1)</script>"))).toBe(false);
    expect(contenidoCoincide("text/csv", Buffer.from("<!DOCTYPE html><html>"))).toBe(false);
    expect(contenidoCoincide("text/plain", Buffer.from([0x41, 0x00, 0x42]))).toBe(false);
  });

  it("normaliza el MIME declarado y rechaza lo que no está en la lista", () => {
    expect(contenidoCoincide("IMAGE/PNG; charset=binary", PNG)).toBe(true);
    expect(mimePermitido("text/html")).toBe(false);
    expect(mimePermitido("image/svg+xml")).toBe(false);
    expect(contenidoCoincide("image/svg+xml", PNG)).toBe(false);
  });
});

describe("mimePorExtension", () => {
  it("deduce el tipo de la extensión", () => {
    expect(mimePorExtension("rx.PNG")).toBe("image/png");
    expect(mimePorExtension("informe.pdf")).toBe("application/pdf");
    expect(mimePorExtension("estudio.dcm")).toBe("application/dicom");
    expect(mimePorExtension("pagina.html")).toBeNull();
  });
});

describe("leerCabecera", () => {
  it("devuelve la cabecera y el archivo completo, sin perder bytes", async () => {
    const trozos = [PNG.subarray(0, 3), PNG.subarray(3), Buffer.alloc(500, 7), Buffer.alloc(10, 9)];
    const { cabecera, cuerpo, bytes } = await leerCabecera(Readable.from(trozos), 132);
    expect(cabecera.subarray(0, 8).equals(PNG.subarray(0, 8))).toBe(true);
    const todo = await leerTodo(cuerpo);
    expect(todo.equals(Buffer.concat(trozos))).toBe(true);
    expect(bytes()).toBe(todo.length);
  });

  it("funciona con archivos más cortos que la cabecera", async () => {
    const { cabecera, cuerpo } = await leerCabecera(Readable.from([Buffer.from("%PDF-")]), 132);
    expect(cabecera.toString()).toBe("%PDF-");
    expect((await leerTodo(cuerpo)).toString()).toBe("%PDF-");
  });

  it("corta el stream al superar el máximo", async () => {
    const trozos = [Buffer.alloc(100), Buffer.alloc(100), Buffer.alloc(100)];
    const { cuerpo } = await leerCabecera(Readable.from(trozos), 10, 250);
    await expect(leerTodo(cuerpo)).rejects.toBeInstanceOf(ArchivoDemasiadoGrande);
  });
});
