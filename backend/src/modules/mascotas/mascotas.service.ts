import { Injectable } from "@nestjs/common";
import { MascotasRepository } from "./mascotas.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";
import { CrearMascotaDto } from "./dto/crear-mascota.dto";
import { ActualizarMascotaDto } from "./dto/actualizar-mascota.dto";
import { ReportarExtravioDto } from "./dto/reportar-extravio.dto";

@Injectable()
export class MascotasService {
  constructor(private readonly repo: MascotasRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.listar(this.ctx(u), f, page, pageSize);
  }
  obtener(u: JwtPayload, id: string) { return this.repo.obtener(this.ctx(u), id); }
  historia(u: JwtPayload, id: string, tipo: string | null, limit: number) {
    return this.repo.historia(this.ctx(u), id, tipo, limit);
  }
  crear(u: JwtPayload, dto: CrearMascotaDto) { return this.repo.crear(this.ctx(u), { ...dto }); }
  actualizar(u: JwtPayload, id: string, dto: ActualizarMascotaDto) {
    return this.repo.actualizar(this.ctx(u), id, { ...dto });
  }
  eliminar(u: JwtPayload, id: string) { return this.repo.eliminar(this.ctx(u), id); }
  carneVacunas(u: JwtPayload, id: string) { return this.repo.carneVacunas(this.ctx(u), id); }
  documentos(u: JwtPayload, id: string) { return this.repo.documentos(this.ctx(u), id); }
  reportarExtravio(u: JwtPayload, dto: ReportarExtravioDto) {
    return this.repo.reportarExtravio(this.ctx(u), { ...dto });
  }
  marcarEncontrada(u: JwtPayload, id: string) { return this.repo.marcarEncontrada(this.ctx(u), id); }
  extraviadas(u: JwtPayload, soloActivos: boolean) {
    return this.repo.extraviadas(this.ctx(u), soloActivos);
  }
}
