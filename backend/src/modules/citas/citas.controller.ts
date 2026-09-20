import {
  BadRequestException, Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query,
} from "@nestjs/common";
import { CitasService } from "./citas.service";
import { CrearCitaDto } from "./dto/crear-cita.dto";
import { ReprogramarCitaDto } from "./dto/reprogramar-cita.dto";
import { CambiarEstadoCitaDto } from "./dto/cambiar-estado-cita.dto";
import { RegistrarLlegadaDto } from "./dto/registrar-llegada.dto";
import { AnotarListaEsperaDto } from "./dto/anotar-lista-espera.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("citas")
export class CitasController {
  constructor(private readonly citas: CitasService) {}

  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
    @Query("estado") estado?: string,
    @Query("veterinarioId") veterinarioId?: string,
    @Query("mascotaId") mascotaId?: string,
    @Query("clienteId") clienteId?: string,
    @Query("buscar") buscar?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const filtros: Record<string, unknown> = {};
    if (desde) filtros.desde = desde;
    if (hasta) filtros.hasta = hasta;
    if (estado) filtros.estado = estado;
    if (veterinarioId) filtros.veterinario_id = veterinarioId;
    if (mascotaId) filtros.mascota_id = mascotaId;
    if (clienteId) filtros.cliente_id = clienteId;
    if (buscar) filtros.buscar = buscar;
    const r = await this.citas.listar(u, filtros, Number(page ?? 1), Number(pageSize ?? 50));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  /** Resumen de la sala de espera: cuántas citas hay en cada estado hoy. */
  @Get("agenda-dia")
  async agendaDia(@CurrentUser() u: JwtPayload, @Query("fecha") fecha?: string) {
    return { ok: true, data: await this.citas.agendaDia(u, fecha ?? null) };
  }

  /** Huecos libres de un veterinario para una fecha. */
  @Get("disponibilidad")
  async disponibilidad(
    @CurrentUser() u: JwtPayload,
    @Query("veterinarioId") veterinarioId: string,
    @Query("fecha") fecha: string,
    @Query("duracion") duracion?: string,
  ) {
    return {
      ok: true,
      data: await this.citas.disponibilidad(
        u, veterinarioId, fecha, duracion ? Number(duracion) : undefined),
    };
  }

  /**
   * Quién está ahora en la clínica esperando, ordenado por gravedad y no por
   * hora de llegada: una emergencia entra antes que un control puntual.
   */
  @Get("sala-espera")
  async salaEspera(@CurrentUser() u: JwtPayload, @Query("veterinarioId") veterinarioId?: string) {
    const f: Record<string, unknown> = {};
    if (veterinarioId) f.veterinario_id = veterinarioId;
    const r = await this.citas.salaEspera(u, f);
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  /** A quién llamar cuando se libera un cupo. */
  @Get("lista-espera")
  async listaEspera(
    @CurrentUser() u: JwtPayload,
    @Query("fecha") fecha?: string,
    @Query("veterinarioId") veterinarioId?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (fecha) f.fecha = fecha;
    if (veterinarioId) f.veterinario_id = veterinarioId;
    return { ok: true, data: await this.citas.listaEsperaListar(u, f) };
  }

  @Get(":id")
  async obtener(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.citas.obtener(u, id) };
  }

  @Post()
  async crear(@CurrentUser() u: JwtPayload, @Body() dto: CrearCitaDto) {
    return { ok: true, data: await this.citas.crear(u, dto) };
  }

  /**
   * El paciente llegó. Con `cita_id` marca la llegada; sin él crea la atención
   * sin cita previa, que es el caso que la agenda no resolvía.
   */
  @Post("llegada")
  async registrarLlegada(@CurrentUser() u: JwtPayload, @Body() dto: RegistrarLlegadaDto) {
    if (!dto.cita_id && !dto.mascota_id) {
      throw new BadRequestException("Indica la cita que llegó o el paciente que se atiende sin cita");
    }
    return { ok: true, data: await this.citas.registrarLlegada(u, dto) };
  }

  @Post("lista-espera")
  async anotarListaEspera(@CurrentUser() u: JwtPayload, @Body() dto: AnotarListaEsperaDto) {
    return { ok: true, data: await this.citas.listaEsperaAnotar(u, dto) };
  }

  @Patch("lista-espera/:id/resolver")
  async resolverListaEspera(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return { ok: true, data: await this.citas.listaEsperaResolver(u, id) };
  }

  @Patch(":id/reprogramar")
  async reprogramar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ReprogramarCitaDto,
  ) {
    return { ok: true, data: await this.citas.reprogramar(u, id, dto) };
  }

  @Patch(":id/estado")
  async cambiarEstado(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CambiarEstadoCitaDto,
  ) {
    return { ok: true, data: await this.citas.cambiarEstado(u, id, dto.estado, dto.motivo) };
  }

  @Delete(":id")
  async eliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.citas.eliminar(u, id) };
  }
}
