import { Injectable } from "@nestjs/common";
import { DashboardRepository } from "./dashboard.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class DashboardService {
  constructor(private readonly repo: DashboardRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  resumen(u: JwtPayload, desde?: string, hasta?: string) {
    return this.repo.resumen(this.ctx(u), desde, hasta);
  }
  recordatorios(u: JwtPayload, dias: number) { return this.repo.recordatorios(this.ctx(u), dias); }
  recordatorioCompletar(u: JwtPayload, id: string) {
    return this.repo.recordatorioCompletar(this.ctx(u), id);
  }
  recordatorioContactar(u: JwtPayload, id: string, p: Record<string, unknown>) {
    return this.repo.recordatorioContactar(this.ctx(u), id, p);
  }
  generarRecordatoriosCitas(u: JwtPayload, dias: number) {
    return this.repo.generarRecordatoriosCitas(this.ctx(u), dias);
  }
  plantillasListar(u: JwtPayload) { return this.repo.plantillasListar(this.ctx(u)); }
  plantillaGuardar(u: JwtPayload, p: Record<string, unknown>) {
    return this.repo.plantillaGuardar(this.ctx(u), p);
  }
}
