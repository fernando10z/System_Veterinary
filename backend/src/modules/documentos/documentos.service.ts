import { Injectable } from "@nestjs/common";
import { DocumentosRepository } from "./documentos.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class DocumentosService {
  constructor(private readonly repo: DocumentosRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  receta(u: JwtPayload, id: string) { return this.repo.receta(this.ctx(u), id); }
  carneVacunacion(u: JwtPayload, id: string) { return this.repo.carneVacunacion(this.ctx(u), id); }
  consentimiento(u: JwtPayload, id: string) { return this.repo.consentimiento(this.ctx(u), id); }
  altaHospitalaria(u: JwtPayload, id: string) { return this.repo.altaHospitalaria(this.ctx(u), id); }
  historiaClinica(u: JwtPayload, id: string) { return this.repo.historiaClinica(this.ctx(u), id); }
  certificadoSalud(u: JwtPayload, id: string, opciones: Record<string, unknown>) {
    return this.repo.certificadoSalud(this.ctx(u), id, opciones);
  }
}
