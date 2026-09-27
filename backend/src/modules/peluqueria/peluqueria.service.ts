import { Injectable } from "@nestjs/common";
import { PeluqueriaRepository } from "./peluqueria.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class PeluqueriaService {
  constructor(private readonly repo: PeluqueriaRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, f: Record<string, unknown>) { return this.repo.listar(this.ctx(u), f); }
  obtener(u: JwtPayload, id: string) { return this.repo.obtener(this.ctx(u), id); }
  recibir(u: JwtPayload, p: Record<string, unknown>) { return this.repo.recibir(this.ctx(u), p); }
  iniciar(u: JwtPayload, id: string) { return this.repo.iniciar(this.ctx(u), id); }
  hallazgo(u: JwtPayload, id: string, p: Record<string, unknown>) {
    return this.repo.hallazgo(this.ctx(u), id, p);
  }
  hallazgoAtender(u: JwtPayload, id: string) { return this.repo.hallazgoAtender(this.ctx(u), id); }
  terminar(u: JwtPayload, id: string, p: Record<string, unknown>) {
    return this.repo.terminar(this.ctx(u), id, p);
  }
  entregar(u: JwtPayload, id: string, p: Record<string, unknown>) {
    return this.repo.entregar(this.ctx(u), id, p);
  }
  cancelar(u: JwtPayload, id: string, motivo?: string) {
    return this.repo.cancelar(this.ctx(u), id, motivo);
  }
}
