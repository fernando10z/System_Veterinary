import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query } from "@nestjs/common";
import { PlanesService } from "./planes.service";
import { GuardarPlanDto } from "./dto/guardar-plan.dto";
import { CancelarSuscripcionDto, SuscribirDto } from "./dto/suscribir.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

/**
 * Planes preventivos. No es el esquema de vacunación —eso es el protocolo
 * clínico y ya existía—: es lo comercial, la cuota que paga el propietario a
 * cambio de tener cubierto el año de salud de su animal.
 *
 * La cobertura se aplica sola al generar cualquier cargo, así que contratar un
 * plan cambia lo que se cobra, no solo lo que dice la ficha.
 */
@Controller("planes")
export class PlanesController {
  constructor(private readonly planes: PlanesService) {}

  @Get()
  async listar(@CurrentUser() u: JwtPayload, @Query("estado") estado?: string) {
    return { ok: true, data: await this.planes.listar(u, estado ? { estado } : {}) };
  }

  @Post()
  async guardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarPlanDto) {
    return { ok: true, data: await this.planes.guardar(u, { ...dto }) };
  }

  @Delete(":id")
  async eliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.planes.eliminar(u, id) };
  }

  // ---- Suscripciones --------------------------------------------------------

  @Get("suscripciones/listar")
  async suscripciones(
    @CurrentUser() u: JwtPayload,
    @Query("estado") estado?: string,
    @Query("planId") planId?: string,
    @Query("clienteId") clienteId?: string,
    @Query("porVencerDias") porVencerDias?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (estado) f.estado = estado;
    if (planId) f.plan_id = planId;
    if (clienteId) f.cliente_id = clienteId;
    if (porVencerDias) f.por_vencer_dias = Number(porVencerDias);
    const r = await this.planes.suscripciones(u, f);
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  @Post("suscripciones")
  async suscribir(@CurrentUser() u: JwtPayload, @Body() dto: SuscribirDto) {
    return { ok: true, data: await this.planes.suscribir(u, { ...dto }) };
  }

  @Patch("suscripciones/:id/cancelar")
  async cancelar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CancelarSuscripcionDto,
  ) {
    return { ok: true, data: await this.planes.cancelar(u, id, dto.motivo) };
  }

  /** Qué le queda al paciente de su plan. Lo que se le enseña al propietario. */
  @Get("mascota/:id")
  async estado(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.planes.estado(u, id) };
  }

  /** Cierra las suscripciones que pasaron de fecha. Idempotente. */
  @Post("vencer")
  async vencer(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.planes.vencer(u) };
  }
}
