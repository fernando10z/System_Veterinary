import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class PagosRepository {
  constructor(private readonly sp: SpExecutorService) {}

  // ---- cobros ----
  registrar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_pago_registrar", ctx, [jsonbArg(p)]);
  }
  anular(ctx: SpContext, id: string, motivo: string) {
    return this.sp.callCtx("app.sp_pago_anular", ctx, [id, motivo]);
  }
  listar(ctx: SpContext, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_pagos_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(f), page, pageSize,
    ]);
  }

  // ---- caja ----
  cajaAbrir(ctx: SpContext, monto: number, observaciones?: string) {
    return this.sp.callCtx<{ id: string }>("app.sp_caja_abrir", ctx, [monto, observaciones ?? null]);
  }
  cajaMovimiento(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_caja_movimiento", ctx, [jsonbArg(p)]);
  }
  cajaCerrar(ctx: SpContext, id: string, montoContado: number, observaciones?: string) {
    return this.sp.callCtx("app.sp_caja_cerrar", ctx, [id, montoContado, observaciones ?? null]);
  }
  cajaActual(ctx: SpContext) {
    return this.sp.callCtx("app.fn_caja_actual", ctx, []);
  }
  cajasListar(ctx: SpContext, f: Record<string, unknown>) {
    return this.sp.callCtx<unknown[]>("app.fn_cajas_listar", ctx, [jsonbArg(f)]);
  }
}
