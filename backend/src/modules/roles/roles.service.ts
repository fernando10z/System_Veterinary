import { Injectable } from "@nestjs/common";
import { RolesRepository } from "./roles.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";
import { CrearRolDto } from "./dto/crear-rol.dto";

@Injectable()
export class RolesService {
  constructor(private readonly repo: RolesRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listarRoles(u: JwtPayload) { return this.repo.listarRoles(this.ctx(u)); }
  listarPermisos(u: JwtPayload) { return this.repo.listarPermisos(this.ctx(u)); }
  crear(u: JwtPayload, dto: CrearRolDto) { return this.repo.crear(this.ctx(u), { ...dto }); }
  setPermisos(u: JwtPayload, rolId: string, codigos: string[]) {
    return this.repo.setPermisos(this.ctx(u), rolId, codigos);
  }
  eliminar(u: JwtPayload, rolId: string) { return this.repo.eliminar(this.ctx(u), rolId); }
}
