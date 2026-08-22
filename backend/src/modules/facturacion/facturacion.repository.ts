import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class FacturacionRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listar(ctx: SpContext, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_comprobantes_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(f), page, pageSize,
    ]);
  }
  obtener(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.fn_comprobante_obtener", ctx, [id]);
  }
  emitir(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_comprobante_emitir", ctx, [jsonbArg(p)]);
  }
  anular(ctx: SpContext, id: string, motivo: string) {
    return this.sp.callCtx("app.sp_comprobante_anular", ctx, [id, motivo]);
  }
  actualizarSunat(ctx: SpContext, id: string, p: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_comprobante_actualizar_sunat", ctx, [id, jsonbArg(p)]);
  }
  cuentasPorCobrar(ctx: SpContext, f: Record<string, unknown>) {
    return this.sp.callRaw<unknown[]>("app.fn_cuentas_por_cobrar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(f),
    ]);
  }
}
