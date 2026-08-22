import { Injectable } from "@nestjs/common";
import { RrhhRepository } from "./rrhh.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class RrhhService {
  constructor(private readonly repo: RrhhRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  disponibilidadListar(u: JwtPayload, desde: string, hasta: string, userId?: string) {
    return this.repo.disponibilidadListar(this.ctx(u), desde, hasta, userId);
  }
  disponibilidadGuardar(u: JwtPayload, d: object) {
    return this.repo.disponibilidadGuardar(this.ctx(u), { ...d });
  }
  disponibilidadEliminar(u: JwtPayload, id: string) {
    return this.repo.disponibilidadEliminar(this.ctx(u), id);
  }

  asistenciaMarcar(u: JwtPayload, targetUserId?: string) {
    return this.repo.asistenciaMarcar(this.ctx(u), targetUserId);
  }
  asistenciaListar(u: JwtPayload, desde: string, hasta: string, userId?: string) {
    return this.repo.asistenciaListar(this.ctx(u), desde, hasta, userId);
  }

  permisoSolicitar(u: JwtPayload, d: object) { return this.repo.permisoSolicitar(this.ctx(u), { ...d }); }
  permisoResolver(u: JwtPayload, id: string, estado: string, comentario?: string) {
    return this.repo.permisoResolver(this.ctx(u), id, estado, comentario);
  }
  permisosListar(u: JwtPayload, f: Record<string, unknown>) {
    return this.repo.permisosListar(this.ctx(u), f);
  }

  contratoGuardar(u: JwtPayload, d: object) { return this.repo.contratoGuardar(this.ctx(u), { ...d }); }
  evaluacionRegistrar(u: JwtPayload, d: object) {
    return this.repo.evaluacionRegistrar(this.ctx(u), { ...d });
  }
  equipoResumen(u: JwtPayload, desde?: string, hasta?: string) {
    return this.repo.equipoResumen(this.ctx(u), desde, hasta);
  }
}
