import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class ClientesRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listar(ctx: SpContext, filtros: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_cliente_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(filtros), page, pageSize,
    ]);
  }
  obtener(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.fn_cliente_obtener", ctx, [id]);
  }
  buscar(ctx: SpContext, q: string, limit: number) {
    return this.sp.callCtx<unknown[]>("app.fn_cliente_buscar", ctx, [q, limit]);
  }
  crear(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_cliente_crear", ctx, [jsonbArg(payload)]);
  }
  actualizar(ctx: SpContext, id: string, payload: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_cliente_actualizar", ctx, [id, jsonbArg(payload)]);
  }
  activarPortal(ctx: SpContext, id: string, password: string) {
    return this.sp.callCtx("app.sp_cliente_activar_portal", ctx, [id, password]);
  }
  eliminar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_cliente_eliminar", ctx, [id]);
  }
  comunicaciones(ctx: SpContext, clienteId: string | null, limit: number) {
    return this.sp.callCtx<unknown[]>("app.fn_comunicaciones_listar", ctx, [clienteId, limit]);
  }
  registrarComunicacion(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_comunicacion_registrar", ctx, [jsonbArg(payload)]);
  }
}
