import { Injectable } from "@nestjs/common";
import { FacturacionRepository } from "./facturacion.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class FacturacionService {
  constructor(private readonly repo: FacturacionRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.listar(this.ctx(u), f, page, pageSize);
  }
  obtener(u: JwtPayload, id: string) { return this.repo.obtener(this.ctx(u), id); }
  emitir(u: JwtPayload, d: object) { return this.repo.emitir(this.ctx(u), { ...d }); }
  anular(u: JwtPayload, id: string, motivo: string) { return this.repo.anular(this.ctx(u), id, motivo); }
  actualizarSunat(u: JwtPayload, id: string, d: object) {
    return this.repo.actualizarSunat(this.ctx(u), id, { ...d });
  }
  cuentasPorCobrar(u: JwtPayload, f: Record<string, unknown>) {
    return this.repo.cuentasPorCobrar(this.ctx(u), f);
  }
}
