import { BadRequestException, Injectable } from "@nestjs/common";
import { MinioService } from "../../infrastructure/storage/minio.service";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

/**
 * Tipos que la clínica sube de verdad: imágenes de diagnóstico, PDFs de
 * laboratorio, consentimientos escaneados. La lista es blanca a propósito —un
 * .html o un .svg servido desde el almacén se ejecuta en el navegador de quien
 * lo abre, y aquí lo que se guarda son documentos, no páginas.
 */
const TIPOS_PERMITIDOS = new Set([
  "image/jpeg", "image/png", "image/webp", "image/gif", "image/bmp", "image/tiff",
  "application/pdf",
  "application/dicom",
  "text/plain", "text/csv",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
]);

const MAX_BYTES = 50 * 1024 * 1024;

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

  private validarTipo(mime?: string): void {
    if (!mime || !TIPOS_PERMITIDOS.has(mime.split(";")[0].trim().toLowerCase())) {
      throw new BadRequestException({
        code: "VALIDATION_ERROR",
        message: `Tipo de archivo no admitido${mime ? `: ${mime}` : ""}`,
      });
    }
  }

  async subir(
    u: JwtPayload,
    area: string,
    filename: string,
    mimetype: string,
    buffer: Buffer,
  ) {
    this.validarTipo(mimetype);
    if (buffer.length > MAX_BYTES) {
      throw new BadRequestException({
        code: "VALIDATION_ERROR",
        message: "El archivo supera los 50 MB",
      });
    }
    // La clave la arma el backend a partir de la empresa del token: el cliente
    // no elige dónde escribe.
    const key = this.minio.buildKey(u.empresa_id, area, filename);
    await this.autorizar(u, key, "subir");
    await this.minio.putObject(key, buffer, mimetype);
    return {
      storage_key: key,
      nombre: filename,
      mime_type: mimetype,
      tamanio_bytes: buffer.length,
    };
  }

  async ticketSubida(u: JwtPayload, area: string, nombre: string) {
    const key = this.minio.buildKey(u.empresa_id, area, nombre);
    await this.autorizar(u, key, "subir");
    const ticket = await this.minio.presignedUploadUrl(key);
    return { storage_key: key, ...ticket };
  }

  async ticketDescarga(u: JwtPayload, key: string) {
    await this.autorizar(u, key, "descargar");
    return this.minio.presignedDownloadUrl(key);
  }
}
