import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class SedesRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listar(ctx: SpContext, f: Record<string, unknown>) {
    return this.sp.callCtx<unknown[]>("app.fn_sedes_listar", ctx, [jsonbArg(f)]);
  }
  guardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_sede_guardar", ctx, [jsonbArg(p)]);
  }
  eliminar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_sede_eliminar", ctx, [id]);
  }
}
