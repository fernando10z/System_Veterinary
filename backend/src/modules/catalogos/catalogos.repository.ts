import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class CatalogosRepository {
  constructor(private readonly sp: SpExecutorService) {}

  especies(ctx: SpContext, incluirInactivos = false) {
    return this.sp.callCtx<unknown[]>("app.fn_especies_listar", ctx, [incluirInactivos]);
  }
  especieGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_especie_guardar", ctx, [jsonbArg(p)]);
  }
  razaGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_raza_guardar", ctx, [jsonbArg(p)]);
  }

  servicios(ctx: SpContext, filtros: Record<string, unknown>) {
    return this.sp.callCtx<unknown[]>("app.fn_servicios_listar", ctx, [jsonbArg(filtros)]);
  }
  servicioGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_servicio_guardar", ctx, [jsonbArg(p)]);
  }
  servicioEliminar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_servicio_eliminar", ctx, [id]);
  }

  categorias(ctx: SpContext, ambito?: string) {
    return this.sp.callCtx<unknown[]>("app.fn_categorias_listar", ctx, [ambito ?? null]);
  }
  categoriaGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_categoria_guardar", ctx, [jsonbArg(p)]);
  }

  consultorios(ctx: SpContext) {
    return this.sp.callCtx<unknown[]>("app.fn_consultorios_listar", ctx, []);
  }
  consultorioGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_consultorio_guardar", ctx, [jsonbArg(p)]);
  }

  horarios(ctx: SpContext) {
    return this.sp.callCtx<unknown[]>("app.fn_horarios_atencion_listar", ctx, []);
  }
  horariosGuardar(ctx: SpContext, horarios: unknown[]) {
    return this.sp.callCtx("app.sp_horarios_atencion_guardar", ctx, [jsonbArg(horarios)]);
  }

  especializaciones(ctx: SpContext) {
    return this.sp.callCtx<unknown[]>("app.fn_especializaciones_listar", ctx, []);
  }
  especializacionGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_especializacion_guardar", ctx, [jsonbArg(p)]);
  }

  esquemasVacunacion(ctx: SpContext, especieId?: string) {
    return this.sp.callCtx<unknown[]>("app.fn_esquemas_vacunacion_listar", ctx, [especieId ?? null]);
  }
  esquemaGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_esquema_vacunacion_guardar", ctx, [jsonbArg(p)]);
  }

  clausulas(ctx: SpContext, tipo?: string) {
    return this.sp.callCtx<unknown[]>("app.fn_clausulas_listar", ctx, [tipo ?? null]);
  }
  clausulaGuardar(ctx: SpContext, p: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_clausula_guardar", ctx, [jsonbArg(p)]);
  }
}
