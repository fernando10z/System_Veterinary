import { Injectable } from "@nestjs/common";
import { UsersRepository } from "./users.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";
import { CrearUsuarioDto } from "./dto/crear-usuario.dto";
import { ActualizarUsuarioDto } from "./dto/actualizar-usuario.dto";

@Injectable()
export class UsersService {
  constructor(private readonly repo: UsersRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, filtros: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.listar(this.ctx(u), filtros, page, pageSize);
  }
  obtener(u: JwtPayload, id: string) {
    return this.repo.obtener(this.ctx(u), id);
  }
  crear(u: JwtPayload, dto: CrearUsuarioDto) {
    return this.repo.crear(this.ctx(u), { ...dto });
  }
  actualizar(u: JwtPayload, id: string, dto: ActualizarUsuarioDto) {
    return this.repo.actualizar(this.ctx(u), id, { ...dto });
  }
  cambiarEstado(u: JwtPayload, id: string, estado: string) {
    return this.repo.cambiarEstado(this.ctx(u), id, estado);
  }
  cambiarRol(u: JwtPayload, id: string, rolId: string, empresaId?: string | null) {
    return this.repo.cambiarRol(this.ctx(u), id, rolId, empresaId);
  }
  resetPassword(u: JwtPayload, id: string, password_temp: string) {
    return this.repo.resetPassword(this.ctx(u), id, password_temp);
  }
  eliminar(u: JwtPayload, id: string) {
    return this.repo.eliminar(this.ctx(u), id);
  }
  veterinarios(u: JwtPayload) {
    return this.repo.veterinarios(this.ctx(u));
  }
}
