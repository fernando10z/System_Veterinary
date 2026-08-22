import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Query } from "@nestjs/common";
import { InventarioService } from "./inventario.service";
import { GuardarProductoDto } from "./dto/guardar-producto.dto";
import { MovimientoInventarioDto } from "./dto/movimiento-inventario.dto";
import { RegistrarLoteDto } from "./dto/registrar-lote.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("inventario")
export class InventarioController {
  constructor(private readonly inv: InventarioService) {}

  @Get("productos")
  async productos(
    @CurrentUser() u: JwtPayload,
    @Query("buscar") buscar?: string,
    @Query("tipo") tipo?: string,
    @Query("estado") estado?: string,
    @Query("categoriaId") categoriaId?: string,
    @Query("soloCriticos") soloCriticos?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (buscar) f.buscar = buscar;
    if (tipo) f.tipo = tipo;
    if (estado) f.estado = estado;
    if (categoriaId) f.categoria_id = categoriaId;
    if (soloCriticos === "true") f.solo_criticos = true;
    const r = await this.inv.productosListar(u, f, Number(page ?? 1), Number(pageSize ?? 20));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  @Post("productos")
  async productoGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarProductoDto) {
    return { ok: true, data: await this.inv.productoGuardar(u, dto) };
  }

  @Delete("productos/:id")
  async productoEliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.inv.productoEliminar(u, id) };
  }

  /** Stock crítico, lotes por vencer y lotes vencidos: lo que exige acción hoy. */
  @Get("alertas")
  async alertas(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.inv.alertas(u) };
  }

  @Get("almacenes")
  async almacenes(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.inv.almacenes(u) };
  }

  @Get("movimientos")
  async movimientos(
    @CurrentUser() u: JwtPayload,
    @Query("productoId") productoId?: string,
    @Query("tipo") tipo?: string,
    @Query("motivo") motivo?: string,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (productoId) f.producto_id = productoId;
    if (tipo) f.tipo = tipo;
    if (motivo) f.motivo = motivo;
    if (desde) f.desde = desde;
    if (hasta) f.hasta = hasta;
    const r = await this.inv.movimientosListar(u, f, Number(page ?? 1), Number(pageSize ?? 50));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  @Post("movimientos")
  async movimiento(@CurrentUser() u: JwtPayload, @Body() dto: MovimientoInventarioDto) {
    return { ok: true, data: await this.inv.movimiento(u, dto) };
  }

  @Post("lotes")
  async lote(@CurrentUser() u: JwtPayload, @Body() dto: RegistrarLoteDto) {
    return { ok: true, data: await this.inv.loteRegistrar(u, dto) };
  }
}
