import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class RrhhRepository {
  constructor(private readonly sp: SpExecutorService) {}

  disponibilidadListar(ctx: SpContext, desde: string, hasta: string, userId?: string) {
    return this.sp.callCtx<unknown[]>("app.fn_disponibilidad_listar", ctx, [
      desde, hasta, userId ?? null,
    ]);
  }
  disponibilidadGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_disponibilidad_guardar", ctx, [jsonbArg(p)]);
  }
  disponibilidadEliminar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_disponibilidad_eliminar", ctx, [id]);
  }

  asistenciaMarcar(ctx: SpContext, targetUserId?: string) {
    return this.sp.callCtx("app.sp_asistencia_marcar", ctx, [targetUserId ?? null]);
  }
  asistenciaListar(ctx: SpContext, desde: string, hasta: string, userId?: string) {
    return this.sp.callRaw<unknown[]>("app.fn_asistencia_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, desde, hasta, userId ?? null,
    ]);
  }

  permisoSolicitar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_permiso_solicitar", ctx, [jsonbArg(p)]);
  }
  permisoResolver(ctx: SpContext, id: string, estado: string, comentario?: string) {
    return this.sp.callCtx("app.sp_permiso_resolver", ctx, [id, estado, comentario ?? null]);
  }
  permisosListar(ctx: SpContext, f: Record<string, unknown>) {
    return this.sp.callCtx<unknown[]>("app.fn_permisos_laborales_listar", ctx, [jsonbArg(f)]);
  }

  contratoGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_contrato_personal_guardar", ctx, [jsonbArg(p)]);
  }
  evaluacionRegistrar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_evaluacion_registrar", ctx, [jsonbArg(p)]);
  }
  equipoResumen(ctx: SpContext, desde?: string, hasta?: string) {
    return this.sp.callRaw<unknown[]>("app.fn_equipo_resumen", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, desde ?? null, hasta ?? null,
    ]);
  }
}
