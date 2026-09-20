import {
  BadRequestException, Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query,
} from "@nestjs/common";
import { FacturacionService } from "./facturacion.service";
import { EmitirComprobanteDto } from "./dto/emitir-comprobante.dto";
import { AnularComprobanteDto } from "./dto/anular-comprobante.dto";
import { ActualizarSunatDto } from "./dto/actualizar-sunat.dto";
import { EmitirNotaCreditoDto } from "./dto/emitir-nota-credito.dto";
import { ComunicarBajaDto } from "./dto/comunicar-baja.dto";
import { PseService } from "./pse/pse.service";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("facturacion")
export class FacturacionController {
  constructor(
    private readonly fact: FacturacionService,
    private readonly pse: PseService,
  ) {}

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

  /** Lo numerado que todavía no llegó a SUNAT: la cola del cierre del día. */
  @Get("sunat/pendientes")
  async pendientesSunat(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.pse.porEnviar(u) };
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

  /**
   * El camino para corregir un comprobante que ya salió. Anularlo solo vale
   * mientras no haya llegado a SUNAT ni se haya cobrado.
   */
  @Post("notas-credito")
  async notaCredito(@CurrentUser() u: JwtPayload, @Body() dto: EmitirNotaCreditoDto) {
    return { ok: true, data: await this.fact.emitirNotaCredito(u, dto) };
  }

  @Patch(":id/anular")
  async anular(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: AnularComprobanteDto,
  ) {
    return { ok: true, data: await this.fact.anular(u, id, dto.motivo) };
  }

  /** Envía el comprobante a SUNAT a través del PSE. Reintentable. */
  @Post(":id/sunat/enviar")
  async enviarSunat(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.pse.enviar(u, id) };
  }

  /** Envía de una vez todo lo que quedó pendiente. */
  @Post("sunat/enviar-pendientes")
  async enviarPendientes(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.pse.enviarPendientes(u) };
  }

  /** Reconsulta el estado: el CDR de SUNAT llega minutos después del envío. */
  @Get(":id/sunat/estado")
  async estadoSunat(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.pse.consultarEstado(u, id) };
  }

  /**
   * Descarga el documento oficial tal como quedó en el proveedor: es el que
   * vale ante SUNAT, no la reimpresión del ERP.
   */
  @Get(":id/sunat/archivo/:tipo")
  async archivoSunat(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("tipo") tipo: string,
  ) {
    const t = String(tipo).toUpperCase();
    if (!["XML", "PDF", "CDR"].includes(t)) {
      throw new BadRequestException("El tipo de archivo debe ser XML, PDF o CDR");
    }
    return { ok: true, data: await this.pse.descargarArchivo(u, id, t as "XML" | "PDF" | "CDR") };
  }

  /**
   * Comunicación de baja: el camino de SUNAT para dar por no emitida una
   * factura dentro del plazo. Para una boleta corresponde la nota de crédito.
   */
  @Patch(":id/sunat/baja")
  async bajaSunat(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ComunicarBajaDto,
  ) {
    return { ok: true, data: await this.pse.comunicarBaja(u, id, dto.motivo) };
  }

  /** Respuesta del PSE/OSE cargada a mano (conciliación manual). */
  @Patch(":id/sunat")
  async sunat(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ActualizarSunatDto,
  ) {
    return { ok: true, data: await this.fact.actualizarSunat(u, id, dto) };
  }
}
