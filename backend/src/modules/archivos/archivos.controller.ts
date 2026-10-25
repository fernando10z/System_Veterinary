import { BadRequestException, Controller, Get, Post, Query, Req } from "@nestjs/common";
import { FastifyRequest } from "fastify";
import { ArchivosService } from "./archivos.service";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

/**
 * Carga y descarga de archivos clínicos (radiografías, resultados, consentimientos).
 *
 * Dos caminos de subida:
 *  - POST /archivos  → el navegador manda el archivo al backend y este lo
 *    empuja a MinIO. Simple, sirve para archivos moderados.
 *  - GET /archivos/ticket-subida → devuelve una política POST firmada para que
 *    el navegador suba directo a MinIO sin pasar por el backend. La política
 *    fija clave, tipo exacto y tamaño máximo; solo para PDF, imágenes y DICOM.
 *
 * En el primero el contenido se comprueba por sus primeros bytes (firma), no
 * solo por el Content-Type que declara el cliente.
 *
 * En ambos casos el backend devuelve la `storage_key`, que es lo que se guarda
 * en la historia clínica (POST /clinico/documentos).
 *
 * Toda clave pasa por `app.fn_archivo_autorizar` antes de firmarse: el almacén
 * no sabe de empresas ni de roles, así que el permiso se resuelve aquí.
 */
@Controller("archivos")
export class ArchivosController {
  constructor(private readonly archivos: ArchivosService) {}

  @Post()
  async subir(@CurrentUser() u: JwtPayload, @Req() req: FastifyRequest) {
    const file = await (req as any).file?.();
    if (!file) {
      throw new BadRequestException({
        code: "VALIDATION_ERROR",
        message: "No se recibió ningún archivo",
      });
    }
    const area = ((req.query as any)?.area as string) || "clinico";
    // Se pasa el stream, no `toBuffer()`: el archivo no se carga en memoria.
    const data = await this.archivos.subir(u, area, file.filename, file.mimetype, file.file);
    // @fastify/multipart corta el stream al llegar a limits.fileSize y marca
    // `truncated`: lo guardado estaría incompleto.
    if (file.file?.truncated) {
      await this.archivos.descartar(data.storage_key);
      throw new BadRequestException({
        code: "VALIDATION_ERROR",
        message: "El archivo supera los 50 MB",
      });
    }
    return { ok: true, data };
  }

  /** Política POST firmada para subir directo a MinIO (archivos grandes). */
  @Get("ticket-subida")
  async ticketSubida(
    @CurrentUser() u: JwtPayload,
    @Query("nombre") nombre: string,
    @Query("area") area?: string,
    @Query("tipo") tipo?: string,
  ) {
    if (!nombre) {
      throw new BadRequestException({
        code: "VALIDATION_ERROR",
        message: "Indica el nombre del archivo",
      });
    }
    return { ok: true, data: await this.archivos.ticketSubida(u, area || "clinico", nombre, tipo) };
  }

  /** URL temporal de descarga a partir de la storage_key guardada. */
  @Get("ticket-descarga")
  async ticketDescarga(@CurrentUser() u: JwtPayload, @Query("key") key: string) {
    return { ok: true, data: await this.archivos.ticketDescarga(u, key) };
  }
}
