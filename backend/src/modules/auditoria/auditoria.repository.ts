import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class AuditoriaRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listar(ctx: SpContext, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_auditoria_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(f), page, pageSize,
    ]);
  }
  notificaciones(ctx: SpContext, soloNoLeidas: boolean, limit: number) {
    return this.sp.callRaw<unknown[]>("app.fn_notificaciones_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, soloNoLeidas, limit,
    ]);
  }
  marcarLeida(ctx: SpContext, id?: string) {
    return this.sp.callCtx("app.sp_notificacion_marcar_leida", ctx, [id ?? null]);
  }
}
