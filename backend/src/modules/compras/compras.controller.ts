import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query } from "@nestjs/common";
import { ComprasService } from "./compras.service";
import { GuardarProveedorDto } from "./dto/guardar-proveedor.dto";
import { GuardarContactoDto } from "./dto/guardar-contacto.dto";
import { CrearOrdenCompraDto } from "./dto/crear-orden-compra.dto";
import { RecibirOrdenDto } from "./dto/recibir-orden.dto";
import { CambiarEstadoOrdenDto } from "./dto/cambiar-estado-orden.dto";
import { RegistrarPagoProveedorDto } from "./dto/registrar-pago-proveedor.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("compras")
export class ComprasController {
  constructor(private readonly compras: ComprasService) {}

  // ---- proveedores ----
  @Get("proveedores")
  async proveedores(
    @CurrentUser() u: JwtPayload,
    @Query("buscar") buscar?: string,
    @Query("estado") estado?: string,
    @Query("categoriaId") categoriaId?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (buscar) f.buscar = buscar;
    if (estado) f.estado = estado;
    if (categoriaId) f.categoria_id = categoriaId;
    const r = await this.compras.proveedoresListar(u, f, Number(page ?? 1), Number(pageSize ?? 20));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  @Post("proveedores")
  async proveedorGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarProveedorDto) {
    return { ok: true, data: await this.compras.proveedorGuardar(u, dto) };
  }

  @Delete("proveedores/:id")
  async proveedorEliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.compras.proveedorEliminar(u, id) };
  }

  @Post("proveedores/contactos")
  async contacto(@CurrentUser() u: JwtPayload, @Body() dto: GuardarContactoDto) {
    return { ok: true, data: await this.compras.contactoGuardar(u, dto) };
  }

  // ---- órdenes de compra ----
  @Get("ordenes")
  async ordenes(
    @CurrentUser() u: JwtPayload,
    @Query("estado") estado?: string,
    @Query("estadoPago") estadoPago?: string,
    @Query("proveedorId") proveedorId?: string,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (estado) f.estado = estado;
    if (estadoPago) f.estado_pago = estadoPago;
    if (proveedorId) f.proveedor_id = proveedorId;
    if (desde) f.desde = desde;
    if (hasta) f.hasta = hasta;
    const r = await this.compras.ordenesListar(u, f, Number(page ?? 1), Number(pageSize ?? 20));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  @Post("ordenes")
  async ordenCrear(@CurrentUser() u: JwtPayload, @Body() dto: CrearOrdenCompraDto) {
    return { ok: true, data: await this.compras.ordenCrear(u, dto) };
  }

  /** Recibir mercadería: es lo que mueve el inventario y crea los lotes. */
  @Post("ordenes/:id/recibir")
  async ordenRecibir(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: RecibirOrdenDto,
  ) {
    return { ok: true, data: await this.compras.ordenRecibir(u, id, dto.recepcion) };
  }

  @Patch("ordenes/:id/estado")
  async ordenEstado(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CambiarEstadoOrdenDto,
  ) {
    return { ok: true, data: await this.compras.ordenCambiarEstado(u, id, dto.estado) };
  }

  // ---- pagos a proveedores ----
  @Get("pagos")
  async pagos(
    @CurrentUser() u: JwtPayload,
    @Query("proveedorId") proveedorId?: string,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (proveedorId) f.proveedor_id = proveedorId;
    if (desde) f.desde = desde;
    if (hasta) f.hasta = hasta;
    return { ok: true, data: await this.compras.pagosListar(u, f) };
  }

  @Post("pagos")
  async pagoRegistrar(@CurrentUser() u: JwtPayload, @Body() dto: RegistrarPagoProveedorDto) {
    return { ok: true, data: await this.compras.pagoRegistrar(u, dto) };
  }
}
