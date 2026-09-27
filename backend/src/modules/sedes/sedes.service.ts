import { Injectable } from "@nestjs/common";
import { SedesRepository } from "./sedes.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class SedesService {
  constructor(private readonly repo: SedesRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, f: Record<string, unknown>) { return this.repo.listar(this.ctx(u), f); }
  guardar(u: JwtPayload, p: Record<string, unknown>) { return this.repo.guardar(this.ctx(u), p); }
  eliminar(u: JwtPayload, id: string) { return this.repo.eliminar(this.ctx(u), id); }
}
