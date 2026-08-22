import { Injectable } from "@nestjs/common";
import { ComprasRepository } from "./compras.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class ComprasService {
  constructor(private readonly repo: ComprasRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  proveedoresListar(u: JwtPayload, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.proveedoresListar(this.ctx(u), f, page, pageSize);
  }
  proveedorGuardar(u: JwtPayload, d: object) { return this.repo.proveedorGuardar(this.ctx(u), { ...d }); }
  proveedorEliminar(u: JwtPayload, id: string) { return this.repo.proveedorEliminar(this.ctx(u), id); }
  contactoGuardar(u: JwtPayload, d: object) { return this.repo.contactoGuardar(this.ctx(u), { ...d }); }

  ordenesListar(u: JwtPayload, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.ordenesListar(this.ctx(u), f, page, pageSize);
  }
  ordenCrear(u: JwtPayload, d: object) { return this.repo.ordenCrear(this.ctx(u), { ...d }); }
  ordenRecibir(u: JwtPayload, id: string, recepcion?: unknown[]) {
    return this.repo.ordenRecibir(this.ctx(u), id, recepcion);
  }
  ordenCambiarEstado(u: JwtPayload, id: string, estado: string) {
    return this.repo.ordenCambiarEstado(this.ctx(u), id, estado);
  }

  pagoRegistrar(u: JwtPayload, d: object) { return this.repo.pagoRegistrar(this.ctx(u), { ...d }); }
  pagosListar(u: JwtPayload, f: Record<string, unknown>) { return this.repo.pagosListar(this.ctx(u), f); }
}
