import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class ComprasRepository {
  constructor(private readonly sp: SpExecutorService) {}

  proveedoresListar(ctx: SpContext, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_proveedores_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(f), page, pageSize,
    ]);
  }
  proveedorGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_proveedor_guardar", ctx, [jsonbArg(p)]);
  }
  proveedorEliminar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_proveedor_eliminar", ctx, [id]);
  }
  contactoGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_proveedor_contacto_guardar", ctx, [jsonbArg(p)]);
  }

  ordenesListar(ctx: SpContext, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_ordenes_compra_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(f), page, pageSize,
    ]);
  }
  ordenCrear(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_orden_compra_crear", ctx, [jsonbArg(p)]);
  }
  ordenRecibir(ctx: SpContext, id: string, recepcion?: unknown[]) {
    return this.sp.callCtx("app.sp_orden_compra_recibir", ctx, [
      id, recepcion ? jsonbArg(recepcion) : null,
    ]);
  }
  ordenCambiarEstado(ctx: SpContext, id: string, estado: string) {
    return this.sp.callCtx("app.sp_orden_compra_cambiar_estado", ctx, [id, estado]);
  }

  pagoRegistrar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_pago_proveedor_registrar", ctx, [jsonbArg(p)]);
  }
  pagosListar(ctx: SpContext, f: Record<string, unknown>) {
    return this.sp.callCtx<unknown[]>("app.fn_pagos_proveedor_listar", ctx, [jsonbArg(f)]);
  }
}
