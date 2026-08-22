import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query } from "@nestjs/common";
import { PagosService } from "./pagos.service";
import { RegistrarPagoDto } from "./dto/registrar-pago.dto";
import { AnularPagoDto } from "./dto/anular-pago.dto";
import { AbrirCajaDto } from "./dto/abrir-caja.dto";
import { CerrarCajaDto } from "./dto/cerrar-caja.dto";
import { MovimientoCajaDto } from "./dto/movimiento-caja.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("pagos")
export class PagosController {
  constructor(private readonly pagos: PagosService) {}

  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("clienteId") clienteId?: string,
    @Query("metodo") metodo?: string,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (clienteId) f.cliente_id = clienteId;
    if (metodo) f.metodo = metodo;
    if (desde) f.desde = desde;
    if (hasta) f.hasta = hasta;
    const r = await this.pagos.listar(u, f, Number(page ?? 1), Number(pageSize ?? 20));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  /**
   * Sin `aplicaciones`, el cobro se imputa a los comprobantes más antiguos
   * hasta agotar el monto.
   */
  @Post()
  async registrar(@CurrentUser() u: JwtPayload, @Body() dto: RegistrarPagoDto) {
    return { ok: true, data: await this.pagos.registrar(u, dto) };
  }

  @Patch(":id/anular")
  async anular(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: AnularPagoDto,
  ) {
    return { ok: true, data: await this.pagos.anular(u, id, dto.motivo) };
  }
}

@Controller("caja")
export class CajaController {
  constructor(private readonly pagos: PagosService) {}

  /** Caja abierta del usuario, con el detalle de movimientos del turno. */
  @Get("actual")
  async actual(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.pagos.cajaActual(u) };
  }

  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("estado") estado?: string,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (estado) f.estado = estado;
    if (desde) f.desde = desde;
    if (hasta) f.hasta = hasta;
    return { ok: true, data: await this.pagos.cajasListar(u, f) };
  }

  @Post("abrir")
  async abrir(@CurrentUser() u: JwtPayload, @Body() dto: AbrirCajaDto) {
    return { ok: true, data: await this.pagos.cajaAbrir(u, dto.monto_apertura ?? 0, dto.observaciones) };
  }

  @Post("movimientos")
  async movimiento(@CurrentUser() u: JwtPayload, @Body() dto: MovimientoCajaDto) {
    return { ok: true, data: await this.pagos.cajaMovimiento(u, dto) };
  }

  /** Arqueo: compara lo contado contra lo esperado y deja la diferencia. */
  @Patch(":id/cerrar")
  async cerrar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CerrarCajaDto,
  ) {
    return { ok: true, data: await this.pagos.cajaCerrar(u, id, dto.monto_contado, dto.observaciones) };
  }
}
