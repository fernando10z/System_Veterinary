import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class InventarioRepository {
  constructor(private readonly sp: SpExecutorService) {}

  productosListar(ctx: SpContext, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_productos_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(f), page, pageSize,
    ]);
  }
  productoGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_producto_guardar", ctx, [jsonbArg(p)]);
  }
  productoEliminar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_producto_eliminar", ctx, [id]);
  }
  movimiento(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_inventario_movimiento", ctx, [jsonbArg(p)]);
  }
  movimientosListar(ctx: SpContext, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_movimientos_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(f), page, pageSize,
    ]);
  }
  alertas(ctx: SpContext) {
    return this.sp.callCtx("app.fn_inventario_alertas", ctx, []);
  }
  almacenes(ctx: SpContext) {
    return this.sp.callCtx<unknown[]>("app.fn_almacenes_listar", ctx, []);
  }
  loteRegistrar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_lote_registrar", ctx, [jsonbArg(p)]);
  }
}
