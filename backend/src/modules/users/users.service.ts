import { Injectable } from "@nestjs/common";
import { UsersRepository } from "./users.repository";
import { SesionesService } from "../../infrastructure/cache/sesiones.service";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";
import { CrearUsuarioDto } from "./dto/crear-usuario.dto";
import { ActualizarUsuarioDto } from "./dto/actualizar-usuario.dto";

@Injectable()
export class UsersService {
  constructor(
    private readonly repo: UsersRepository,
    private readonly sesiones: SesionesService,
  ) {}

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
  // Las operaciones que quitan o cambian el acceso cierran además las sesiones
  // abiertas del usuario. El SP ya se ejecutó (si falla, lanza y no se llega
  // aquí): solo se revoca lo que la base aceptó.
  async cambiarEstado(u: JwtPayload, id: string, estado: string) {
    const data = await this.repo.cambiarEstado(this.ctx(u), id, estado);
    if (estado !== "activo") await this.sesiones.revocarTodas(id);
    return data;
  }
  /** Con el rol cambian los permisos: las sesiones con el rol viejo se cierran. */
  async cambiarRol(u: JwtPayload, id: string, rolId: string, empresaId?: string | null) {
    const data = await this.repo.cambiarRol(this.ctx(u), id, rolId, empresaId);
    await this.sesiones.revocarTodas(id);
    return data;
  }
  async resetPassword(u: JwtPayload, id: string, password_temp: string) {
    const data = await this.repo.resetPassword(this.ctx(u), id, password_temp);
    await this.sesiones.revocarTodas(id);
    return data;
  }
  async eliminar(u: JwtPayload, id: string) {
    const data = await this.repo.eliminar(this.ctx(u), id);
    await this.sesiones.revocarTodas(id);
    return data;
  }
  veterinarios(u: JwtPayload) {
    return this.repo.veterinarios(this.ctx(u));
  }
}
