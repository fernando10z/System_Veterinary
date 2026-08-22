import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class CitasRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listar(ctx: SpContext, filtros: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_citas_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(filtros), page, pageSize,
    ]);
  }
  agendaDia(ctx: SpContext, fecha: string | null) {
    return this.sp.callCtx("app.fn_citas_agenda_dia", ctx, [fecha]);
  }
  disponibilidad(ctx: SpContext, veterinarioId: string, fecha: string, duracion?: number) {
    return this.sp.callCtx("app.fn_citas_disponibilidad", ctx, [
      veterinarioId, fecha, duracion ?? null,
    ]);
  }
  obtener(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.fn_cita_obtener", ctx, [id]);
  }
  crear(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_cita_crear", ctx, [jsonbArg(payload)]);
  }
  reprogramar(ctx: SpContext, id: string, fechaHora: string, motivo?: string, vetId?: string) {
    return this.sp.callCtx("app.sp_cita_reprogramar", ctx, [
      id, fechaHora, motivo ?? null, vetId ?? null,
    ]);
  }
  cambiarEstado(ctx: SpContext, id: string, estado: string, motivo?: string) {
    return this.sp.callCtx("app.sp_cita_cambiar_estado", ctx, [id, estado, motivo ?? null]);
  }
  eliminar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_cita_eliminar", ctx, [id]);
  }
}
