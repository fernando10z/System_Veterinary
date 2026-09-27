import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class PlanesRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listar(ctx: SpContext, f: Record<string, unknown>) {
    return this.sp.callCtx<unknown[]>("app.fn_planes_listar", ctx, [jsonbArg(f)]);
  }
  guardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_plan_guardar", ctx, [jsonbArg(p)]);
  }
  eliminar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_plan_eliminar", ctx, [id]);
  }
  suscripciones(ctx: SpContext, f: Record<string, unknown>) {
    return this.sp.callRaw<unknown[]>("app.fn_suscripciones_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(f),
    ]);
  }
  suscribir(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_suscripcion_crear", ctx, [jsonbArg(p)]);
  }
  cancelar(ctx: SpContext, id: string, motivo?: string) {
    return this.sp.callCtx("app.sp_suscripcion_cancelar", ctx, [id, motivo ?? null]);
  }
  estado(ctx: SpContext, mascotaId: string) {
    return this.sp.callCtx("app.fn_suscripcion_estado", ctx, [mascotaId]);
  }
  vencer(ctx: SpContext) {
    return this.sp.callCtx("app.sp_suscripciones_vencer", ctx, []);
  }
}
