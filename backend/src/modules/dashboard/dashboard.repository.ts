import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class DashboardRepository {
  constructor(private readonly sp: SpExecutorService) {}

  resumen(ctx: SpContext, desde?: string, hasta?: string) {
    return this.sp.callCtx("app.fn_dashboard_resumen", ctx, [desde ?? null, hasta ?? null]);
  }
  recordatorios(ctx: SpContext, dias: number) {
    return this.sp.callCtx<unknown[]>("app.fn_recordatorios_listar", ctx, [dias]);
  }
  recordatorioCompletar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_recordatorio_completar", ctx, [id]);
  }
}
