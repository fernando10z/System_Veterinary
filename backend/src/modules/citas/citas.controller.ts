import {
  Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query,
} from "@nestjs/common";
import { CitasService } from "./citas.service";
import { CrearCitaDto } from "./dto/crear-cita.dto";
import { ReprogramarCitaDto } from "./dto/reprogramar-cita.dto";
import { CambiarEstadoCitaDto } from "./dto/cambiar-estado-cita.dto";
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

  @Get(":id")
  async obtener(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.citas.obtener(u, id) };
  }

  @Post()
  async crear(@CurrentUser() u: JwtPayload, @Body() dto: CrearCitaDto) {
    return { ok: true, data: await this.citas.crear(u, dto) };
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
