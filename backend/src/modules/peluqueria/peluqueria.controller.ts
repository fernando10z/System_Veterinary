import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query } from "@nestjs/common";
import { PeluqueriaService } from "./peluqueria.service";
import { RecibirPeluqueriaDto } from "./dto/recibir.dto";
import { HallazgoDto } from "./dto/hallazgo.dto";
import {
  CancelarPeluqueriaDto, EntregarPeluqueriaDto, TerminarPeluqueriaDto,
} from "./dto/cerrar.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

/**
 * Peluquería. Un baño con corte son cuatro horas con el animal solo y la
 * clínica respondiendo por él: eso es una estancia, no una cita.
 *
 * El recorrido: recibir → iniciar → (hallazgos) → terminar → entregar.
 */
@Controller("peluqueria")
export class PeluqueriaController {
  constructor(private readonly pel: PeluqueriaService) {}

  /** Tablero del día: quién está dentro y en qué estado. */
  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
    @Query("estado") estado?: string,
    @Query("sedeId") sedeId?: string,
    @Query("mascotaId") mascotaId?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (desde) f.desde = desde;
    if (hasta) f.hasta = hasta;
    if (estado) f.estado = estado;
    if (sedeId) f.sede_id = sedeId;
    if (mascotaId) f.mascota_id = mascotaId;
    const r = await this.pel.listar(u, f);
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  @Get(":id")
  async obtener(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.pel.obtener(u, id) };
  }

  /** El animal entra: servicios pedidos y estado en que llegó. */
  @Post()
  async recibir(@CurrentUser() u: JwtPayload, @Body() dto: RecibirPeluqueriaDto) {
    return { ok: true, data: await this.pel.recibir(u, { ...dto }) };
  }

  @Patch(":id/iniciar")
  async iniciar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.pel.iniciar(u, id) };
  }

  /** Lo que se le vio mientras se le bañaba. Entra en la historia clínica. */
  @Post(":id/hallazgos")
  async hallazgo(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: HallazgoDto,
  ) {
    return { ok: true, data: await this.pel.hallazgo(u, id, { ...dto }) };
  }

  /** El veterinario da por revisado un hallazgo urgente. */
  @Patch("hallazgos/:id/atender")
  async atender(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.pel.hallazgoAtender(u, id) };
  }

  /** Trabajo hecho: genera los cargos y deja la sesión en la historia. */
  @Patch(":id/terminar")
  async terminar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: TerminarPeluqueriaDto,
  ) {
    return { ok: true, data: await this.pel.terminar(u, id, { ...dto }) };
  }

  @Patch(":id/entregar")
  async entregar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: EntregarPeluqueriaDto,
  ) {
    return { ok: true, data: await this.pel.entregar(u, id, { ...dto }) };
  }

  @Patch(":id/cancelar")
  async cancelar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CancelarPeluqueriaDto,
  ) {
    return { ok: true, data: await this.pel.cancelar(u, id, dto.motivo) };
  }
}
