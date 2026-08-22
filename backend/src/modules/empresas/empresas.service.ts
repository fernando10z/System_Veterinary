import { Injectable } from "@nestjs/common";
import { EmpresasRepository } from "./empresas.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";
import { GuardarEmpresaDto } from "./dto/guardar-empresa.dto";

@Injectable()
export class EmpresasService {
  constructor(private readonly repo: EmpresasRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, filtros: Record<string, unknown>) {
    return this.repo.listar(this.ctx(u), filtros);
  }
  obtener(u: JwtPayload, id?: string) { return this.repo.obtener(this.ctx(u), id); }
  crear(u: JwtPayload, dto: GuardarEmpresaDto) { return this.repo.crear(this.ctx(u), { ...dto }); }
  actualizar(u: JwtPayload, id: string, dto: GuardarEmpresaDto) {
    return this.repo.actualizar(this.ctx(u), id, { ...dto });
  }
}
