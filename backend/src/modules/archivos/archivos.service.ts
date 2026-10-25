import { BadRequestException, Injectable } from "@nestjs/common";
import { MinioService } from "../../infrastructure/storage/minio.service";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";
import {
  ArchivoDemasiadoGrande, MAX_BYTES, TIPOS, contenidoCoincide, leerCabecera,
  mimePermitido, mimePorExtension, normalizarMime,
} from "./tipo-archivo";

/**
 * Tipos que la clínica sube de verdad: imágenes de diagnóstico, PDFs de
 * laboratorio, consentimientos escaneados. La lista es blanca a propósito —un
 * .html o un .svg servido desde el almacén se ejecuta en el navegador de quien
 * lo abre, y aquí lo que se guarda son documentos, no páginas—. La lista y las
 * firmas de contenido viven en tipo-archivo.ts.
 */
const invalido = (message: string) =>
  new BadRequestException({ code: "VALIDATION_ERROR", message });

@Injectable()
export class ArchivosService {
  constructor(
    private readonly minio: MinioService,
    private readonly sp: SpExecutorService,
  ) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  /** La base decide: empresa dueña del objeto, área válida y permiso. */
  private autorizar(u: JwtPayload, key: string, modo: "subir" | "descargar") {
    return this.sp.callCtx("app.fn_archivo_autorizar", this.ctx(u), [key, modo]);
  }

  private validarTipo(mime?: string): string {
    const m = normalizarMime(mime);
    if (!mimePermitido(m)) {
      throw invalido(`Tipo de archivo no admitido${mime ? `: ${mime}` : ""}`);
    }
    return m;
  }

  /**
   * Subida a través del backend. El archivo llega como stream y se reenvía a
   * MinIO sin cargarlo entero en memoria; antes de reenviarlo se leen sus
   * primeros bytes y se comprueba que el contenido sea del tipo declarado.
   */
  async subir(
    u: JwtPayload,
    area: string,
    filename: string,
    mimetype: string,
    contenido: AsyncIterable<Buffer | string>,
  ) {
    const mime = this.validarTipo(mimetype);
    // La clave la arma el backend a partir de la empresa del token: el cliente
    // no elige dónde escribe.
    const key = this.minio.buildKey(u.empresa_id, area, filename);
    await this.autorizar(u, key, "subir");

    let lectura: Awaited<ReturnType<typeof leerCabecera>>;
    try {
      lectura = await leerCabecera(contenido);
    } catch (err) {
      if (err instanceof ArchivoDemasiadoGrande) throw invalido("El archivo supera los 50 MB");
      throw err;
    }
    if (lectura.cabecera.length === 0) throw invalido("El archivo está vacío");
    if (!contenidoCoincide(mime, lectura.cabecera)) {
      throw invalido(`El contenido del archivo no corresponde a ${mime}`);
    }

    try {
      await this.minio.putObjectStream(key, lectura.cuerpo, mime);
    } catch (err) {
      // Si el stream se cortó por tamaño, lo que MinIO llegó a guardar se borra.
      await this.minio.deleteObject(key).catch(() => undefined);
      if (err instanceof ArchivoDemasiadoGrande) throw invalido("El archivo supera los 50 MB");
      throw err;
    }
    return {
      storage_key: key,
      nombre: filename,
      mime_type: mime,
      tamanio_bytes: lectura.bytes(),
    };
  }

  /**
   * Ticket de subida directa a MinIO (POST con política firmada). Solo para
   * tipos binarios con firma fuerte: por este camino el backend no ve el
   * contenido, así que la política fija al menos el tipo exacto y el tamaño.
   * El tipo se toma de `tipo` o, si no viene, de la extensión del nombre.
   */
  async ticketSubida(u: JwtPayload, area: string, nombre: string, tipo?: string) {
    const key = this.minio.buildKey(u.empresa_id, area, nombre);
    await this.autorizar(u, key, "subir");
    const mime = normalizarMime(tipo) || mimePorExtension(nombre) || "";
    if (!TIPOS[mime]?.directa) {
      throw invalido(
        `Ese tipo de archivo${mime ? ` (${mime})` : ""} se sube por POST /api/archivos, no con ticket`,
      );
    }
    const ticket = await this.minio.presignedUploadPost(key, mime, MAX_BYTES);
    return { storage_key: key, metodo: "POST", mime_type: mime, max_bytes: MAX_BYTES, ...ticket };
  }

  descartar(key: string) {
    return this.minio.deleteObject(key).catch(() => undefined);
  }

  async ticketDescarga(u: JwtPayload, key: string) {
    await this.autorizar(u, key, "descargar");
    return this.minio.presignedDownloadUrl(key);
  }
}
