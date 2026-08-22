import { Injectable } from "@nestjs/common";
import { InventarioRepository } from "./inventario.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class InventarioService {
  constructor(private readonly repo: InventarioRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  productosListar(u: JwtPayload, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.productosListar(this.ctx(u), f, page, pageSize);
  }
  productoGuardar(u: JwtPayload, d: object) { return this.repo.productoGuardar(this.ctx(u), { ...d }); }
  productoEliminar(u: JwtPayload, id: string) { return this.repo.productoEliminar(this.ctx(u), id); }
  movimiento(u: JwtPayload, d: object) { return this.repo.movimiento(this.ctx(u), { ...d }); }
  movimientosListar(u: JwtPayload, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.movimientosListar(this.ctx(u), f, page, pageSize);
  }
  alertas(u: JwtPayload) { return this.repo.alertas(this.ctx(u)); }
  almacenes(u: JwtPayload) { return this.repo.almacenes(this.ctx(u)); }
  loteRegistrar(u: JwtPayload, d: object) { return this.repo.loteRegistrar(this.ctx(u), { ...d }); }
}
