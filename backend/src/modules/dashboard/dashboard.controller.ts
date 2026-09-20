import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query } from "@nestjs/common";
import { DashboardService } from "./dashboard.service";
import { ContactarRecordatorioDto } from "./dto/contactar-recordatorio.dto";
import { GuardarPlantillaDto } from "./dto/guardar-plantilla.dto";
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

  /**
   * Se contactó al propietario: marca el recordatorio como enviado y deja el
   * contacto en la bitácora del cliente. No lo cierra —enviado y respondido
   * son cosas distintas— salvo que se pida con `completar`.
   */
  @Patch("recordatorios/:id/contactar")
  async contactar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ContactarRecordatorioDto,
  ) {
    return { ok: true, data: await this.dash.recordatorioContactar(u, id, { ...dto }) };
  }

  /** Arma la tanda de avisos de las citas próximas. Idempotente. */
  @Post("recordatorios/generar-citas")
  async generarCitas(@CurrentUser() u: JwtPayload, @Query("dias") dias?: string) {
    return { ok: true, data: await this.dash.generarRecordatoriosCitas(u, Number(dias ?? 1)) };
  }

  /** El texto con el que la clínica contacta a sus propietarios. */
  @Get("plantillas")
  async plantillas(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.dash.plantillasListar(u) };
  }

  @Post("plantillas")
  async guardarPlantilla(@CurrentUser() u: JwtPayload, @Body() dto: GuardarPlantillaDto) {
    return { ok: true, data: await this.dash.plantillaGuardar(u, { ...dto }) };
  }
}
