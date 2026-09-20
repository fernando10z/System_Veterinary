import { Injectable } from "@nestjs/common";
import { EmpresasRepository } from "./empresas.repository";
import { CryptoService } from "../../infrastructure/crypto/crypto.service";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";
import { GuardarEmpresaDto } from "./dto/guardar-empresa.dto";

@Injectable()
export class EmpresasService {
  constructor(
    private readonly repo: EmpresasRepository,
    private readonly crypto: CryptoService,
  ) {}

  /**
   * La clave del PSE viaja en claro desde el formulario y se cifra aquí: a la
   * base sólo llega el blob. Si el campo viene vacío es que no se tocó, y no
   * debe pisar la que ya estaba guardada.
   */
  private cifrarClavePse(dto: GuardarEmpresaDto): Record<string, unknown> {
    const { pse_password, ...resto } = dto as Record<string, unknown> & { pse_password?: string };
    if (!pse_password) return resto;
    return { ...resto, pse_password_enc: this.crypto.encrypt(pse_password) };
  }

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, filtros: Record<string, unknown>) {
    return this.repo.listar(this.ctx(u), filtros);
  }
  obtener(u: JwtPayload, id?: string) { return this.repo.obtener(this.ctx(u), id); }
  crear(u: JwtPayload, dto: GuardarEmpresaDto) {
    return this.repo.crear(this.ctx(u), this.cifrarClavePse(dto));
  }
  actualizar(u: JwtPayload, id: string, dto: GuardarEmpresaDto) {
    return this.repo.actualizar(this.ctx(u), id, this.cifrarClavePse(dto));
  }
}
