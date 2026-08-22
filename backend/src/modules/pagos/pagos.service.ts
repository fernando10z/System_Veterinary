import { Injectable } from "@nestjs/common";
import { PagosRepository } from "./pagos.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class PagosService {
  constructor(private readonly repo: PagosRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  registrar(u: JwtPayload, d: object) { return this.repo.registrar(this.ctx(u), { ...d }); }
  anular(u: JwtPayload, id: string, motivo: string) { return this.repo.anular(this.ctx(u), id, motivo); }
  listar(u: JwtPayload, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.listar(this.ctx(u), f, page, pageSize);
  }

  cajaAbrir(u: JwtPayload, monto: number, obs?: string) {
    return this.repo.cajaAbrir(this.ctx(u), monto, obs);
  }
  cajaMovimiento(u: JwtPayload, d: object) { return this.repo.cajaMovimiento(this.ctx(u), { ...d }); }
  cajaCerrar(u: JwtPayload, id: string, monto: number, obs?: string) {
    return this.repo.cajaCerrar(this.ctx(u), id, monto, obs);
  }
  cajaActual(u: JwtPayload) { return this.repo.cajaActual(this.ctx(u)); }
  cajasListar(u: JwtPayload, f: Record<string, unknown>) { return this.repo.cajasListar(this.ctx(u), f); }
}
