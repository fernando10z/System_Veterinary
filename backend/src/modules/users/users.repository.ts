import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext, SpResult } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class UsersRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listar(ctx: SpContext, filtros: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_users_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(filtros), page, pageSize,
    ]);
  }

  obtener(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.fn_users_obtener", ctx, [id]);
  }

  crear(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_users_crear", ctx, [jsonbArg(payload)]);
  }

  actualizar(ctx: SpContext, id: string, payload: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_users_actualizar", ctx, [id, jsonbArg(payload)]);
  }

  cambiarEstado(ctx: SpContext, id: string, estado: string) {
    return this.sp.callCtx("app.sp_users_cambiar_estado", ctx, [id, estado]);
  }

  cambiarRol(ctx: SpContext, id: string, rolId: string, empresaId?: string | null) {
    return this.sp.callCtx("app.sp_users_cambiar_rol", ctx, [id, rolId, empresaId ?? null]);
  }

  resetPassword(ctx: SpContext, id: string, passwordTemp: string) {
    return this.sp.callCtx("app.sp_users_reset_password", ctx, [id, passwordTemp]);
  }

  eliminar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_users_eliminar", ctx, [id]);
  }

  veterinarios(ctx: SpContext) {
    return this.sp.callCtx<unknown[]>("app.fn_veterinarios_listar", ctx, []);
  }
}
