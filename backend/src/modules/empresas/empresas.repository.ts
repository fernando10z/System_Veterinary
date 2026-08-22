import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class EmpresasRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listar(ctx: SpContext, filtros: Record<string, unknown>) {
    return this.sp.callCtx<unknown[]>("app.fn_empresa_listar", ctx, [jsonbArg(filtros)]);
  }
  obtener(ctx: SpContext, id?: string) {
    return this.sp.callCtx("app.fn_empresa_obtener", ctx, [id ?? null]);
  }
  crear(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_empresa_crear", ctx, [jsonbArg(payload)]);
  }
  actualizar(ctx: SpContext, id: string, payload: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_empresa_actualizar", ctx, [id, jsonbArg(payload)]);
  }
}
