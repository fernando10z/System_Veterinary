import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class RolesRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listarRoles(ctx: SpContext) {
    return this.sp.callCtx<unknown[]>("app.fn_roles_listar", ctx, []);
  }
  listarPermisos(ctx: SpContext) {
    return this.sp.callCtx<unknown[]>("app.fn_permisos_listar", ctx, []);
  }
  crear(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_rol_crear", ctx, [jsonbArg(payload)]);
  }
  setPermisos(ctx: SpContext, rolId: string, codigos: string[]) {
    return this.sp.callCtx("app.sp_rol_set_permisos", ctx, [rolId, jsonbArg(codigos)]);
  }
  eliminar(ctx: SpContext, rolId: string) {
    return this.sp.callCtx("app.sp_rol_eliminar", ctx, [rolId]);
  }
}
