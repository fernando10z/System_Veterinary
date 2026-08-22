import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class MascotasRepository {
  constructor(private readonly sp: SpExecutorService) {}

  listar(ctx: SpContext, filtros: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_mascota_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(filtros), page, pageSize,
    ]);
  }
  obtener(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.fn_mascota_obtener", ctx, [id]);
  }
  historia(ctx: SpContext, mascotaId: string, tipo: string | null, limit: number) {
    return this.sp.callCtx<unknown[]>("app.fn_mascota_historia", ctx, [mascotaId, tipo, limit]);
  }
  crear(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_mascota_crear", ctx, [jsonbArg(payload)]);
  }
  actualizar(ctx: SpContext, id: string, payload: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_mascota_actualizar", ctx, [id, jsonbArg(payload)]);
  }
  eliminar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_mascota_eliminar", ctx, [id]);
  }
  carneVacunas(ctx: SpContext, mascotaId: string) {
    return this.sp.callCtx<unknown[]>("app.fn_vacunas_carne", ctx, [mascotaId]);
  }
  documentos(ctx: SpContext, mascotaId: string) {
    return this.sp.callCtx<unknown[]>("app.fn_documentos_medicos_listar", ctx, [mascotaId]);
  }
  reportarExtravio(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_mascota_reportar_extravio", ctx, [jsonbArg(payload)]);
  }
  marcarEncontrada(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_mascota_marcar_encontrada", ctx, [id]);
  }
  extraviadas(ctx: SpContext, soloActivos: boolean) {
    return this.sp.callCtx<unknown[]>("app.fn_mascotas_extraviadas_listar", ctx, [soloActivos]);
  }
}
