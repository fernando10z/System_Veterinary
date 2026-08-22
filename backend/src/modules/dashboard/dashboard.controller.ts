import { Controller, Get, Param, ParseUUIDPipe, Patch, Query } from "@nestjs/common";
import { DashboardService } from "./dashboard.service";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("dashboard")
export class DashboardController {
  constructor(private readonly dash: DashboardService) {}

  @Get()
  async resumen(
    @CurrentUser() u: JwtPayload,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
  ) {
    return { ok: true, data: await this.dash.resumen(u, desde, hasta) };
  }

  /** Cola de contactos: refuerzos de vacuna, controles y desparasitaciones. */
  @Get("recordatorios")
  async recordatorios(@CurrentUser() u: JwtPayload, @Query("dias") dias?: string) {
    return { ok: true, data: await this.dash.recordatorios(u, Number(dias ?? 7)) };
  }

  @Patch("recordatorios/:id/completar")
  async completar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.dash.recordatorioCompletar(u, id) };
  }
}
