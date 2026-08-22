import { Injectable } from "@nestjs/common";
import { ReportesRepository } from "./reportes.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class ReportesService {
  constructor(private readonly repo: ReportesRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  ventas(u: JwtPayload, d: string, h: string) { return this.repo.ventas(this.ctx(u), d, h); }
  clinico(u: JwtPayload, d: string, h: string) { return this.repo.clinico(this.ctx(u), d, h); }
  inventario(u: JwtPayload, d?: string, h?: string) { return this.repo.inventario(this.ctx(u), d, h); }
  ejecutivo(u: JwtPayload, d: string, h: string) { return this.repo.ejecutivo(this.ctx(u), d, h); }
}
