import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, UseGuards } from "@nestjs/common";
import { PortalService } from "./portal.service";
import { SolicitarCitaPortalDto } from "./dto/solicitar-cita-portal.dto";
import { CambiarPasswordPortalDto } from "./dto/cambiar-password-portal.dto";
import { Public } from "../../common/decorators/public.decorator";
import { PortalAuthGuard } from "../../common/guards/portal-auth.guard";
import { CurrentCliente } from "../../common/decorators/current-cliente.decorator";

/**
 * @Public() desactiva el guard del backoffice; PortalAuthGuard aplica en su
 * lugar la validación del token del propietario.
 */
@Public()
@UseGuards(PortalAuthGuard)
@Controller("portal")
export class PortalController {
  constructor(private readonly portal: PortalService) {}

  @Get("mis-mascotas")
  async misMascotas(@CurrentCliente() clienteId: string) {
    return { ok: true, data: await this.portal.misMascotas(clienteId) };
  }

  @Get("mis-citas")
  async misCitas(@CurrentCliente() clienteId: string, @Query("pasadas") pasadas?: string) {
    return { ok: true, data: await this.portal.misCitas(clienteId, pasadas !== "false") };
  }

  /** Historia clínica en versión propietario: sin notas internas del equipo. */
  @Get("mascotas/:id/historial")
  async historial(
    @CurrentCliente() clienteId: string,
    @Param("id", ParseUUIDPipe) mascotaId: string,
  ) {
    return { ok: true, data: await this.portal.historial(clienteId, mascotaId) };
  }

  @Get("mis-comprobantes")
  async misComprobantes(@CurrentCliente() clienteId: string) {
    return { ok: true, data: await this.portal.misComprobantes(clienteId) };
  }

  /** La cita entra como solicitud: recepción la confirma. */
  @Post("citas")
  async solicitarCita(
    @CurrentCliente() clienteId: string,
    @Body() dto: SolicitarCitaPortalDto,
  ) {
    return { ok: true, data: await this.portal.solicitarCita(clienteId, dto) };
  }

  @Post("cambiar-password")
  async cambiarPassword(
    @CurrentCliente() clienteId: string,
    @Body() dto: CambiarPasswordPortalDto,
  ) {
    return {
      ok: true,
      data: await this.portal.cambiarPassword(clienteId, dto.passwordActual, dto.passwordNuevo),
    };
  }
}
