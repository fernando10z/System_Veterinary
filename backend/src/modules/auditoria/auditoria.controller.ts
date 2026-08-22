import { Controller, Get, Param, ParseUUIDPipe, Patch, Query } from "@nestjs/common";
import { AuditoriaService } from "./auditoria.service";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("auditoria")
export class AuditoriaController {
  constructor(private readonly aud: AuditoriaService) {}

  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("entidad") entidad?: string,
    @Query("accion") accion?: string,
    @Query("userId") userId?: string,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (entidad) f.entidad = entidad;
    if (accion) f.accion = accion;
    if (userId) f.user_id = userId;
    if (desde) f.desde = desde;
    if (hasta) f.hasta = hasta;
    const r = await this.aud.listar(u, f, Number(page ?? 1), Number(pageSize ?? 50));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }
}

@Controller("notificaciones")
export class NotificacionesController {
  constructor(private readonly aud: AuditoriaService) {}

  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("soloNoLeidas") soloNoLeidas?: string,
    @Query("limit") limit?: string,
  ) {
    const r = await this.aud.notificaciones(u, soloNoLeidas === "true", Number(limit ?? 30));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  /** Sin id marca todas las del usuario. */
  @Patch("leidas")
  async marcarTodas(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.aud.marcarLeida(u) };
  }

  @Patch(":id/leida")
  async marcar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.aud.marcarLeida(u, id) };
  }
}
