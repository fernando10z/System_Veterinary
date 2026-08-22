import {
  Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query,
} from "@nestjs/common";
import { ClinicoService } from "./clinico.service";
import { CrearConsultaDto } from "./dto/crear-consulta.dto";
import { ActualizarConsultaDto } from "./dto/actualizar-consulta.dto";
import { AplicarVacunaDto } from "./dto/aplicar-vacuna.dto";
import { RegistrarDesparasitacionDto } from "./dto/registrar-desparasitacion.dto";
import { RegistrarTratamientoDto } from "./dto/registrar-tratamiento.dto";
import { ProgramarCirugiaDto } from "./dto/programar-cirugia.dto";
import { ResultadoCirugiaDto } from "./dto/resultado-cirugia.dto";
import { IngresarHospitalizacionDto } from "./dto/ingresar-hospitalizacion.dto";
import { EvolucionHospitalizacionDto } from "./dto/evolucion-hospitalizacion.dto";
import { AltaHospitalizacionDto } from "./dto/alta-hospitalizacion.dto";
import { RegistrarExamenDto } from "./dto/registrar-examen.dto";
import { CrearNotaDto } from "./dto/crear-nota.dto";
import { RegistrarDocumentoDto } from "./dto/registrar-documento.dto";
import { CrearOrdenServicioDto } from "./dto/crear-orden-servicio.dto";
import { ConsumirInsumoDto } from "./dto/consumir-insumo.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("clinico")
export class ClinicoController {
  constructor(private readonly clinico: ClinicoService) {}

  // ---------------------------------------------------------------- consultas
  @Get("consultas")
  async consultasListar(
    @CurrentUser() u: JwtPayload,
    @Query("mascotaId") mascotaId?: string,
    @Query("veterinarioId") veterinarioId?: string,
    @Query("estado") estado?: string,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (mascotaId) f.mascota_id = mascotaId;
    if (veterinarioId) f.veterinario_id = veterinarioId;
    if (estado) f.estado = estado;
    if (desde) f.desde = desde;
    if (hasta) f.hasta = hasta;
    const r = await this.clinico.consultasListar(u, f, Number(page ?? 1), Number(pageSize ?? 20));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  @Get("consultas/:id")
  async consultaObtener(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.clinico.consultaObtener(u, id) };
  }

  @Post("consultas")
  async consultaCrear(@CurrentUser() u: JwtPayload, @Body() dto: CrearConsultaDto) {
    return { ok: true, data: await this.clinico.consultaCrear(u, dto) };
  }

  @Patch("consultas/:id")
  async consultaActualizar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ActualizarConsultaDto,
  ) {
    return { ok: true, data: await this.clinico.consultaActualizar(u, id, dto) };
  }

  /** Firma la consulta y completa la cita asociada. Exige diagnóstico. */
  @Patch("consultas/:id/cerrar")
  async consultaCerrar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.clinico.consultaCerrar(u, id) };
  }

  // ------------------------------------------------- vacunas y desparasitación
  @Post("vacunas")
  async vacunaAplicar(@CurrentUser() u: JwtPayload, @Body() dto: AplicarVacunaDto) {
    return { ok: true, data: await this.clinico.vacunaAplicar(u, dto) };
  }

  @Post("desparasitaciones")
  async desparasitacion(@CurrentUser() u: JwtPayload, @Body() dto: RegistrarDesparasitacionDto) {
    return { ok: true, data: await this.clinico.desparasitacionRegistrar(u, dto) };
  }

  // ------------------------------------------------------------- tratamientos
  @Post("tratamientos")
  async tratamiento(@CurrentUser() u: JwtPayload, @Body() dto: RegistrarTratamientoDto) {
    return { ok: true, data: await this.clinico.tratamientoRegistrar(u, dto) };
  }

  @Patch("tratamientos/:id/estado")
  async tratamientoEstado(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body("estado") estado: string,
  ) {
    return { ok: true, data: await this.clinico.tratamientoCambiarEstado(u, id, estado) };
  }

  // ------------------------------------------------------------------ cirugías
  @Get("cirugias")
  async cirugiasListar(
    @CurrentUser() u: JwtPayload,
    @Query("estado") estado?: string,
    @Query("mascotaId") mascotaId?: string,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (estado) f.estado = estado;
    if (mascotaId) f.mascota_id = mascotaId;
    if (desde) f.desde = desde;
    if (hasta) f.hasta = hasta;
    return { ok: true, data: await this.clinico.cirugiasListar(u, f) };
  }

  @Post("cirugias")
  async cirugiaProgramar(@CurrentUser() u: JwtPayload, @Body() dto: ProgramarCirugiaDto) {
    return { ok: true, data: await this.clinico.cirugiaProgramar(u, dto) };
  }

  @Patch("cirugias/:id/resultado")
  async cirugiaResultado(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ResultadoCirugiaDto,
  ) {
    return { ok: true, data: await this.clinico.cirugiaRegistrarResultado(u, id, dto) };
  }

  // ------------------------------------------------------------ hospitalización
  @Get("hospitalizaciones")
  async hospListar(@CurrentUser() u: JwtPayload, @Query("todas") todas?: string) {
    return { ok: true, data: await this.clinico.hospitalizacionesListar(u, todas !== "true") };
  }

  @Post("hospitalizaciones")
  async hospIngresar(@CurrentUser() u: JwtPayload, @Body() dto: IngresarHospitalizacionDto) {
    return { ok: true, data: await this.clinico.hospitalizacionIngresar(u, dto) };
  }

  @Post("hospitalizaciones/evoluciones")
  async hospEvolucion(@CurrentUser() u: JwtPayload, @Body() dto: EvolucionHospitalizacionDto) {
    return { ok: true, data: await this.clinico.hospitalizacionEvolucion(u, dto) };
  }

  @Patch("hospitalizaciones/:id/alta")
  async hospAlta(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: AltaHospitalizacionDto,
  ) {
    return { ok: true, data: await this.clinico.hospitalizacionAlta(u, id, dto) };
  }

  // ------------------------------------------------ exámenes, notas, documentos
  @Post("examenes")
  async examen(@CurrentUser() u: JwtPayload, @Body() dto: RegistrarExamenDto) {
    return { ok: true, data: await this.clinico.examenRegistrar(u, dto) };
  }

  @Post("notas")
  async nota(@CurrentUser() u: JwtPayload, @Body() dto: CrearNotaDto) {
    return { ok: true, data: await this.clinico.notaCrear(u, dto) };
  }

  @Post("documentos")
  async documento(@CurrentUser() u: JwtPayload, @Body() dto: RegistrarDocumentoDto) {
    return { ok: true, data: await this.clinico.documentoRegistrar(u, dto) };
  }

  // ------------------------------------------------------ órdenes e insumos
  @Post("ordenes-servicio")
  async ordenServicio(@CurrentUser() u: JwtPayload, @Body() dto: CrearOrdenServicioDto) {
    return { ok: true, data: await this.clinico.ordenServicioCrear(u, dto) };
  }

  @Post("insumos")
  async insumo(@CurrentUser() u: JwtPayload, @Body() dto: ConsumirInsumoDto) {
    return { ok: true, data: await this.clinico.insumoConsumir(u, dto) };
  }

  /** Servicios e insumos aún no cobrados de un cliente: alimenta la facturación. */
  @Get("pendiente-facturar/:clienteId")
  async pendiente(
    @CurrentUser() u: JwtPayload,
    @Param("clienteId", ParseUUIDPipe) clienteId: string,
  ) {
    return { ok: true, data: await this.clinico.pendienteFacturar(u, clienteId) };
  }
}
