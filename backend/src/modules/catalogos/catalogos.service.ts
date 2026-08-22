import { Injectable } from "@nestjs/common";
import { CatalogosRepository } from "./catalogos.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class CatalogosService {
  constructor(private readonly repo: CatalogosRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  especies(u: JwtPayload, inc: boolean) { return this.repo.especies(this.ctx(u), inc); }
  especieGuardar(u: JwtPayload, d: object) { return this.repo.especieGuardar(this.ctx(u), { ...d }); }
  razaGuardar(u: JwtPayload, d: object) { return this.repo.razaGuardar(this.ctx(u), { ...d }); }

  servicios(u: JwtPayload, f: Record<string, unknown>) { return this.repo.servicios(this.ctx(u), f); }
  servicioGuardar(u: JwtPayload, d: object) { return this.repo.servicioGuardar(this.ctx(u), { ...d }); }
  servicioEliminar(u: JwtPayload, id: string) { return this.repo.servicioEliminar(this.ctx(u), id); }

  categorias(u: JwtPayload, ambito?: string) { return this.repo.categorias(this.ctx(u), ambito); }
  categoriaGuardar(u: JwtPayload, d: object) { return this.repo.categoriaGuardar(this.ctx(u), { ...d }); }

  consultorios(u: JwtPayload) { return this.repo.consultorios(this.ctx(u)); }
  consultorioGuardar(u: JwtPayload, d: object) { return this.repo.consultorioGuardar(this.ctx(u), { ...d }); }

  horarios(u: JwtPayload) { return this.repo.horarios(this.ctx(u)); }
  horariosGuardar(u: JwtPayload, h: unknown[]) { return this.repo.horariosGuardar(this.ctx(u), h); }

  especializaciones(u: JwtPayload) { return this.repo.especializaciones(this.ctx(u)); }
  especializacionGuardar(u: JwtPayload, d: object) {
    return this.repo.especializacionGuardar(this.ctx(u), { ...d });
  }

  esquemasVacunacion(u: JwtPayload, especieId?: string) {
    return this.repo.esquemasVacunacion(this.ctx(u), especieId);
  }
  esquemaGuardar(u: JwtPayload, d: object) { return this.repo.esquemaGuardar(this.ctx(u), { ...d }); }

  clausulas(u: JwtPayload, tipo?: string) { return this.repo.clausulas(this.ctx(u), tipo); }
  clausulaGuardar(u: JwtPayload, d: object) { return this.repo.clausulaGuardar(this.ctx(u), { ...d }); }
}
