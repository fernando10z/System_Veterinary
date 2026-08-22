import { Injectable } from "@nestjs/common";
import { AuditoriaRepository } from "./auditoria.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class AuditoriaService {
  constructor(private readonly repo: AuditoriaRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.listar(this.ctx(u), f, page, pageSize);
  }
  notificaciones(u: JwtPayload, soloNoLeidas: boolean, limit: number) {
    return this.repo.notificaciones(this.ctx(u), soloNoLeidas, limit);
  }
  marcarLeida(u: JwtPayload, id?: string) { return this.repo.marcarLeida(this.ctx(u), id); }
}
