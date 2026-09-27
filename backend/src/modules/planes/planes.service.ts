import { Injectable } from "@nestjs/common";
import { PlanesRepository } from "./planes.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class PlanesService {
  constructor(private readonly repo: PlanesRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, f: Record<string, unknown>) { return this.repo.listar(this.ctx(u), f); }
  guardar(u: JwtPayload, p: Record<string, unknown>) { return this.repo.guardar(this.ctx(u), p); }
  eliminar(u: JwtPayload, id: string) { return this.repo.eliminar(this.ctx(u), id); }
  suscripciones(u: JwtPayload, f: Record<string, unknown>) {
    return this.repo.suscripciones(this.ctx(u), f);
  }
  suscribir(u: JwtPayload, p: Record<string, unknown>) { return this.repo.suscribir(this.ctx(u), p); }
  cancelar(u: JwtPayload, id: string, motivo?: string) {
    return this.repo.cancelar(this.ctx(u), id, motivo);
  }
  estado(u: JwtPayload, mascotaId: string) { return this.repo.estado(this.ctx(u), mascotaId); }
  vencer(u: JwtPayload) { return this.repo.vencer(this.ctx(u)); }
}
