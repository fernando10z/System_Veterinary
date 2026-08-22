import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query } from "@nestjs/common";
import { RrhhService } from "./rrhh.service";
import { GuardarDisponibilidadDto } from "./dto/guardar-disponibilidad.dto";
import { SolicitarPermisoDto } from "./dto/solicitar-permiso.dto";
import { ResolverPermisoDto } from "./dto/resolver-permiso.dto";
import { GuardarContratoDto } from "./dto/guardar-contrato.dto";
import { RegistrarEvaluacionDto } from "./dto/registrar-evaluacion.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("rrhh")
export class RrhhController {
  constructor(private readonly rrhh: RrhhService) {}

  /** Carga, asistencia y evaluación de cada miembro del equipo. */
  @Get("equipo")
  async equipo(
    @CurrentUser() u: JwtPayload,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
  ) {
    const r = await this.rrhh.equipoResumen(u, desde, hasta);
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  // ---- turnos ----
  @Get("disponibilidad")
  async disponibilidad(
    @CurrentUser() u: JwtPayload,
    @Query("desde") desde: string,
    @Query("hasta") hasta: string,
    @Query("userId") userId?: string,
  ) {
    return { ok: true, data: await this.rrhh.disponibilidadListar(u, desde, hasta, userId) };
  }

  @Post("disponibilidad")
  async disponibilidadGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarDisponibilidadDto) {
    return { ok: true, data: await this.rrhh.disponibilidadGuardar(u, dto) };
  }

  @Delete("disponibilidad/:id")
  async disponibilidadEliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.rrhh.disponibilidadEliminar(u, id) };
  }

  // ---- asistencia ----
  @Get("asistencia")
  async asistencia(
    @CurrentUser() u: JwtPayload,
    @Query("desde") desde: string,
    @Query("hasta") hasta: string,
    @Query("userId") userId?: string,
  ) {
    const r = await this.rrhh.asistenciaListar(u, desde, hasta, userId);
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  /** Un solo endpoint: marca entrada o salida según el estado del día. */
  @Post("asistencia/marcar")
  async marcar(@CurrentUser() u: JwtPayload, @Body("userId") userId?: string) {
    return { ok: true, data: await this.rrhh.asistenciaMarcar(u, userId) };
  }

  // ---- permisos y vacaciones ----
  @Get("permisos")
  async permisos(
    @CurrentUser() u: JwtPayload,
    @Query("estado") estado?: string,
    @Query("userId") userId?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (estado) f.estado = estado;
    if (userId) f.user_id = userId;
    return { ok: true, data: await this.rrhh.permisosListar(u, f) };
  }

  @Post("permisos")
  async permisoSolicitar(@CurrentUser() u: JwtPayload, @Body() dto: SolicitarPermisoDto) {
    return { ok: true, data: await this.rrhh.permisoSolicitar(u, dto) };
  }

  @Patch("permisos/:id/resolver")
  async permisoResolver(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ResolverPermisoDto,
  ) {
    return { ok: true, data: await this.rrhh.permisoResolver(u, id, dto.estado, dto.comentario) };
  }

  // ---- contratos y evaluaciones ----
  @Post("contratos")
  async contrato(@CurrentUser() u: JwtPayload, @Body() dto: GuardarContratoDto) {
    return { ok: true, data: await this.rrhh.contratoGuardar(u, dto) };
  }

  @Post("evaluaciones")
  async evaluacion(@CurrentUser() u: JwtPayload, @Body() dto: RegistrarEvaluacionDto) {
    return { ok: true, data: await this.rrhh.evaluacionRegistrar(u, dto) };
  }
}
