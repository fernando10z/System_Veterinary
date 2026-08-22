import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query } from "@nestjs/common";
import { FacturacionService } from "./facturacion.service";
import { EmitirComprobanteDto } from "./dto/emitir-comprobante.dto";
import { AnularComprobanteDto } from "./dto/anular-comprobante.dto";
import { ActualizarSunatDto } from "./dto/actualizar-sunat.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("facturacion")
export class FacturacionController {
  constructor(private readonly fact: FacturacionService) {}

  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("buscar") buscar?: string,
    @Query("tipo") tipo?: string,
    @Query("estado") estado?: string,
    @Query("estadoPago") estadoPago?: string,
    @Query("clienteId") clienteId?: string,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (buscar) f.buscar = buscar;
    if (tipo) f.tipo = tipo;
    if (estado) f.estado = estado;
    if (estadoPago) f.estado_pago = estadoPago;
    if (clienteId) f.cliente_id = clienteId;
    if (desde) f.desde = desde;
    if (hasta) f.hasta = hasta;
    const r = await this.fact.listar(u, f, Number(page ?? 1), Number(pageSize ?? 20));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  /** Aging de la deuda por cliente y tramo de vencimiento. */
  @Get("cuentas-por-cobrar")
  async cxc(@CurrentUser() u: JwtPayload, @Query("clienteId") clienteId?: string) {
    const f: Record<string, unknown> = {};
    if (clienteId) f.cliente_id = clienteId;
    const r = await this.fact.cuentasPorCobrar(u, f);
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  @Get(":id")
  async obtener(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.fact.obtener(u, id) };
  }

  /**
   * Sin `items`, se factura todo lo pendiente del cliente (servicios prestados
   * e insumos consumidos). Ese es el flujo normal desde recepción.
   */
  @Post()
  async emitir(@CurrentUser() u: JwtPayload, @Body() dto: EmitirComprobanteDto) {
    return { ok: true, data: await this.fact.emitir(u, dto) };
  }

  @Patch(":id/anular")
  async anular(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: AnularComprobanteDto,
  ) {
    return { ok: true, data: await this.fact.anular(u, id, dto.motivo) };
  }

  /** Respuesta del PSE/OSE tras enviar el comprobante a SUNAT. */
  @Patch(":id/sunat")
  async sunat(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ActualizarSunatDto,
  ) {
    return { ok: true, data: await this.fact.actualizarSunat(u, id, dto) };
  }
}
