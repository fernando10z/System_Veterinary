import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";
import { jsonbArg } from "../../infrastructure/database/sp-args";

@Injectable()
export class DocumentosRepository {
  constructor(private readonly sp: SpExecutorService) {}

  receta(ctx: SpContext, consultaId: string) {
    return this.sp.callCtx("app.fn_doc_receta", ctx, [consultaId]);
  }
  carneVacunacion(ctx: SpContext, mascotaId: string) {
    return this.sp.callCtx("app.fn_doc_carne_vacunacion", ctx, [mascotaId]);
  }
  consentimiento(ctx: SpContext, cirugiaId: string) {
    return this.sp.callCtx("app.fn_doc_consentimiento", ctx, [cirugiaId]);
  }
  altaHospitalaria(ctx: SpContext, hospitalizacionId: string) {
    return this.sp.callCtx("app.fn_doc_alta_hospitalaria", ctx, [hospitalizacionId]);
  }
  certificadoSalud(ctx: SpContext, mascotaId: string, opciones: Record<string, unknown>) {
    return this.sp.callCtx("app.fn_doc_certificado_salud", ctx, [mascotaId, jsonbArg(opciones)]);
  }
  historiaClinica(ctx: SpContext, mascotaId: string) {
    return this.sp.callCtx("app.fn_doc_historia_clinica", ctx, [mascotaId]);
  }
}
