import { Injectable } from "@nestjs/common";
import { ClinicoRepository } from "./clinico.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class ClinicoService {
  constructor(private readonly repo: ClinicoRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  // consultas
  consultasListar(u: JwtPayload, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.consultasListar(this.ctx(u), f, page, pageSize);
  }
  consultaObtener(u: JwtPayload, id: string) { return this.repo.consultaObtener(this.ctx(u), id); }
  consultaCrear(u: JwtPayload, dto: object) { return this.repo.consultaCrear(this.ctx(u), { ...dto }); }
  consultaActualizar(u: JwtPayload, id: string, dto: object) {
    return this.repo.consultaActualizar(this.ctx(u), id, { ...dto });
  }
  consultaCerrar(u: JwtPayload, id: string) { return this.repo.consultaCerrar(this.ctx(u), id); }

  // vacunas / desparasitación
  vacunaAplicar(u: JwtPayload, dto: object) { return this.repo.vacunaAplicar(this.ctx(u), { ...dto }); }
  desparasitacionRegistrar(u: JwtPayload, dto: object) {
    return this.repo.desparasitacionRegistrar(this.ctx(u), { ...dto });
  }

  // tratamientos
  tratamientoRegistrar(u: JwtPayload, dto: object) {
    return this.repo.tratamientoRegistrar(this.ctx(u), { ...dto });
  }
  tratamientoCambiarEstado(u: JwtPayload, id: string, estado: string) {
    return this.repo.tratamientoCambiarEstado(this.ctx(u), id, estado);
  }

  // cirugías
  cirugiasListar(u: JwtPayload, f: Record<string, unknown>) {
    return this.repo.cirugiasListar(this.ctx(u), f);
  }
  cirugiaProgramar(u: JwtPayload, dto: object) {
    return this.repo.cirugiaProgramar(this.ctx(u), { ...dto });
  }
  cirugiaRegistrarResultado(u: JwtPayload, id: string, dto: object) {
    return this.repo.cirugiaRegistrarResultado(this.ctx(u), id, { ...dto });
  }

  // hospitalización
  hospitalizacionesListar(u: JwtPayload, soloActivas: boolean) {
    return this.repo.hospitalizacionesListar(this.ctx(u), soloActivas);
  }
  hospitalizacionIngresar(u: JwtPayload, dto: object) {
    return this.repo.hospitalizacionIngresar(this.ctx(u), { ...dto });
  }
  hospitalizacionEvolucion(u: JwtPayload, dto: object) {
    return this.repo.hospitalizacionEvolucion(this.ctx(u), { ...dto });
  }
  hospitalizacionAlta(u: JwtPayload, id: string, dto: object) {
    return this.repo.hospitalizacionAlta(this.ctx(u), id, { ...dto });
  }

  // exámenes, notas, documentos
  examenRegistrar(u: JwtPayload, dto: object) { return this.repo.examenRegistrar(this.ctx(u), { ...dto }); }
  notaCrear(u: JwtPayload, dto: object) { return this.repo.notaCrear(this.ctx(u), { ...dto }); }
  documentoRegistrar(u: JwtPayload, dto: object) {
    return this.repo.documentoRegistrar(this.ctx(u), { ...dto });
  }

  // facturable
  ordenServicioCrear(u: JwtPayload, dto: object) {
    return this.repo.ordenServicioCrear(this.ctx(u), { ...dto });
  }
  insumoConsumir(u: JwtPayload, dto: object) { return this.repo.insumoConsumir(this.ctx(u), { ...dto }); }
  pendienteFacturar(u: JwtPayload, clienteId: string) {
    return this.repo.pendienteFacturar(this.ctx(u), clienteId);
  }
}
