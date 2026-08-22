import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class ReportesRepository {
  constructor(private readonly sp: SpExecutorService) {}

  ventas(ctx: SpContext, desde: string, hasta: string) {
    return this.sp.callCtx("app.fn_reporte_ventas", ctx, [desde, hasta]);
  }
  clinico(ctx: SpContext, desde: string, hasta: string) {
    return this.sp.callCtx("app.fn_reporte_clinico", ctx, [desde, hasta]);
  }
  inventario(ctx: SpContext, desde?: string, hasta?: string) {
    return this.sp.callCtx("app.fn_reporte_inventario", ctx, [desde ?? null, hasta ?? null]);
  }
  ejecutivo(ctx: SpContext, desde: string, hasta: string) {
    return this.sp.callCtx("app.fn_reporte_ejecutivo", ctx, [desde, hasta]);
  }
}
