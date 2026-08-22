import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

/**
 * Repositorio unificado del dominio clínico. Las sub-features (consultas,
 * vacunas, cirugías, hospitalización…) comparten repositorio para permitir
 * orquestación entre ellas sin acoplamiento HTTP.
 */
@Injectable()
export class ClinicoRepository {
  constructor(private readonly sp: SpExecutorService) {}

  // ---- consultas ----
  consultasListar(ctx: SpContext, filtros: Record<string, unknown>, page: number, pageSize: number) {
    return this.sp.callRaw<unknown[]>("app.fn_consultas_listar", [
      ctx.userId, ctx.empresaId, ctx.isSuperAdmin, jsonbArg(filtros), page, pageSize,
    ]);
  }
  consultaObtener(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.fn_consulta_obtener", ctx, [id]);
  }
  consultaCrear(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_consulta_crear", ctx, [jsonbArg(payload)]);
  }
  consultaActualizar(ctx: SpContext, id: string, payload: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_consulta_actualizar", ctx, [id, jsonbArg(payload)]);
  }
  consultaCerrar(ctx: SpContext, id: string) {
    return this.sp.callCtx("app.sp_consulta_cerrar", ctx, [id]);
  }

  // ---- vacunas y desparasitaciones ----
  vacunaAplicar(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_vacuna_aplicar", ctx, [jsonbArg(payload)]);
  }
  desparasitacionRegistrar(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_desparasitacion_registrar", ctx, [jsonbArg(payload)]);
  }

  // ---- tratamientos ----
  tratamientoRegistrar(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_tratamiento_registrar", ctx, [jsonbArg(payload)]);
  }
  tratamientoCambiarEstado(ctx: SpContext, id: string, estado: string) {
    return this.sp.callCtx("app.sp_tratamiento_cambiar_estado", ctx, [id, estado]);
  }

  // ---- cirugías ----
  cirugiasListar(ctx: SpContext, filtros: Record<string, unknown>) {
    return this.sp.callCtx<unknown[]>("app.fn_cirugias_listar", ctx, [jsonbArg(filtros)]);
  }
  cirugiaProgramar(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_cirugia_programar", ctx, [jsonbArg(payload)]);
  }
  cirugiaRegistrarResultado(ctx: SpContext, id: string, payload: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_cirugia_registrar_resultado", ctx, [id, jsonbArg(payload)]);
  }

  // ---- hospitalización ----
  hospitalizacionesListar(ctx: SpContext, soloActivas: boolean) {
    return this.sp.callCtx<unknown[]>("app.fn_hospitalizaciones_listar", ctx, [soloActivas]);
  }
  hospitalizacionIngresar(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_hospitalizacion_ingresar", ctx, [jsonbArg(payload)]);
  }
  hospitalizacionEvolucion(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_hospitalizacion_evolucion", ctx, [jsonbArg(payload)]);
  }
  hospitalizacionAlta(ctx: SpContext, id: string, payload: Record<string, unknown>) {
    return this.sp.callCtx("app.sp_hospitalizacion_alta", ctx, [id, jsonbArg(payload)]);
  }

  // ---- exámenes, notas y documentos ----
  examenRegistrar(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_examen_registrar", ctx, [jsonbArg(payload)]);
  }
  notaCrear(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_nota_medica_crear", ctx, [jsonbArg(payload)]);
  }
  documentoRegistrar(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_documento_medico_registrar", ctx, [jsonbArg(payload)]);
  }

  // ---- lo facturable de la atención ----
  ordenServicioCrear(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_orden_servicio_crear", ctx, [jsonbArg(payload)]);
  }
  insumoConsumir(ctx: SpContext, payload: Record<string, unknown>) {
    return this.sp.callCtx<{ id: string }>("app.sp_insumo_consumir", ctx, [jsonbArg(payload)]);
  }
  pendienteFacturar(ctx: SpContext, clienteId: string) {
    return this.sp.callCtx("app.fn_pendiente_facturar", ctx, [clienteId]);
  }
}
