import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class PeluqueriaRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listar(ctx: SpContext, f: Record<string, unknown>) {
    return this.sp.callRaw<unknown[]>("app.fn_peluqueria_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(f),
    ]);
  }
  obtener(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.fn_peluqueria_obtener", ctx, [id]);
  }
  recibir(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_peluqueria_recibir", ctx, [jsonbArg(p)]);
  }
  iniciar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_peluqueria_iniciar", ctx, [id]);
  }
  hallazgo(ctx: SpContext, id: string, p: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_peluqueria_hallazgo", ctx, [id, jsonbArg(p)]);
  }
  hallazgoAtender(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_peluqueria_hallazgo_atender", ctx, [id]);
  }
  terminar(ctx: SpContext, id: string, p: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_peluqueria_terminar", ctx, [id, jsonbArg(p)]);
  }
  entregar(ctx: SpContext, id: string, p: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_peluqueria_entregar", ctx, [id, jsonbArg(p)]);
  }
  cancelar(ctx: SpContext, id: string, motivo?: string) {
    return this.sp.callCtx("app.sp_peluqueria_cancelar", ctx, [id, motivo ?? null]);
  }
}
