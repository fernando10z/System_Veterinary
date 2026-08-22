import {
  BadRequestException, Body, Controller, Get, Post, Query, Req,
} from "@nestjs/common";
import { FastifyRequest } from "fastify";
import { MinioService } from "../../infrastructure/storage/minio.service";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

/**
 * Carga de archivos clínicos (radiografías, resultados, consentimientos).
 *
 * Dos caminos:
 *  - POST /archivos  → el navegador manda el archivo al backend y este lo
 *    empuja a MinIO. Simple, sirve para archivos moderados.
 *  - GET /archivos/ticket-subida → devuelve una URL prefirmada para que el
 *    navegador suba directo a MinIO sin pasar por el backend (archivos grandes).
 *
 * En ambos casos el backend devuelve la `storage_key`, que es lo que se guarda
 * en la historia clínica (POST /clinico/documentos).
 */
@Controller("archivos")
export class ArchivosController {
  constructor(private readonly minio: MinioService) {}

  @Post()
  async subir(@CurrentUser() u: JwtPayload, @Req() req: FastifyRequest) {
    const file = await (req as any).file?.();
    if (!file) {
      throw new BadRequestException({
        code: "VALIDATION_ERROR",
        message: "No se recibió ningún archivo",
      });
    }

    const buffer = await file.toBuffer();
    const area = ((req.query as any)?.area as string) || "clinico";
    const key = this.minio.buildKey(u.empresa_id, area, file.filename);

    await this.minio.putObject(key, buffer, file.mimetype);

    return {
      ok: true,
      data: {
        storage_key: key,
        nombre: file.filename,
        mime_type: file.mimetype,
        tamanio_bytes: buffer.length,
      },
    };
  }

  /** URL prefirmada de subida directa a MinIO (archivos grandes). */
  @Get("ticket-subida")
  async ticketSubida(
    @CurrentUser() u: JwtPayload,
    @Query("nombre") nombre: string,
    @Query("area") area?: string,
  ) {
    if (!nombre) {
      throw new BadRequestException({
        code: "VALIDATION_ERROR",
        message: "Indica el nombre del archivo",
      });
    }
    const key = this.minio.buildKey(u.empresa_id, area || "clinico", nombre);
    const ticket = await this.minio.presignedUploadUrl(key);
    return { ok: true, data: { storage_key: key, ...ticket } };
  }

  /** URL temporal de descarga a partir de la storage_key guardada. */
  @Get("ticket-descarga")
  async ticketDescarga(@Query("key") key: string) {
    if (!key) {
      throw new BadRequestException({
        code: "VALIDATION_ERROR",
        message: "Indica la clave del archivo",
      });
    }
    const ticket = await this.minio.presignedDownloadUrl(key);
    return { ok: true, data: ticket };
  }
}
