import { Controller, Get, Param, ParseUUIDPipe, Query } from "@nestjs/common";
import { DocumentosService } from "./documentos.service";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

/**
 * Los papeles que la clínica entrega: receta, carné, consentimiento, alta,
 * certificado de salud e historia clínica.
 *
 * Todos son lecturas: devuelven el documento armado y el cliente lo imprime.
 * Emitir un documento no cambia el estado de nada —firmar el consentimiento,
 * por ejemplo, sigue siendo un acto aparte en el módulo clínico.
 */
@Controller("documentos")
export class DocumentosController {
  constructor(private readonly docs: DocumentosService) {}

  @Get("receta/:consultaId")
  async receta(@CurrentUser() u: JwtPayload, @Param("consultaId", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.docs.receta(u, id) };
  }

  @Get("carne-vacunacion/:mascotaId")
  async carne(@CurrentUser() u: JwtPayload, @Param("mascotaId", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.docs.carneVacunacion(u, id) };
  }

  @Get("consentimiento/:cirugiaId")
  async consentimiento(@CurrentUser() u: JwtPayload, @Param("cirugiaId", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.docs.consentimiento(u, id) };
  }

  @Get("alta-hospitalaria/:hospitalizacionId")
  async alta(
    @CurrentUser() u: JwtPayload,
    @Param("hospitalizacionId", ParseUUIDPipe) id: string,
  ) {
    return { ok: true, data: await this.docs.altaHospitalaria(u, id) };
  }

  /**
   * El certificado se devuelve siempre; si falta la antirrábica vigente o el
   * examen reciente, viene con `apto: false` y el detalle de qué falta, para
   * que el veterinario lo vea antes de firmar.
   */
  @Get("certificado-salud/:mascotaId")
  async certificado(
    @CurrentUser() u: JwtPayload,
    @Param("mascotaId", ParseUUIDPipe) id: string,
    @Query("motivo") motivo?: string,
    @Query("destino") destino?: string,
    @Query("veterinarioId") veterinarioId?: string,
  ) {
    const opciones: Record<string, unknown> = {};
    if (motivo) opciones.motivo = motivo;
    if (destino) opciones.destino = destino;
    if (veterinarioId) opciones.veterinario_id = veterinarioId;
    return { ok: true, data: await this.docs.certificadoSalud(u, id, opciones) };
  }

  @Get("historia-clinica/:mascotaId")
  async historia(@CurrentUser() u: JwtPayload, @Param("mascotaId", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.docs.historiaClinica(u, id) };
  }
}
