import { Injectable } from "@nestjs/common";
import { CitasRepository } from "./citas.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";
import { CrearCitaDto } from "./dto/crear-cita.dto";
import { ReprogramarCitaDto } from "./dto/reprogramar-cita.dto";

@Injectable()
export class CitasService {
  constructor(private readonly repo: CitasRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, f: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.listar(this.ctx(u), f, page, pageSize);
  }
  agendaDia(u: JwtPayload, fecha: string | null) { return this.repo.agendaDia(this.ctx(u), fecha); }
  disponibilidad(u: JwtPayload, vetId: string, fecha: string, duracion?: number) {
    return this.repo.disponibilidad(this.ctx(u), vetId, fecha, duracion);
  }
  obtener(u: JwtPayload, id: string) { return this.repo.obtener(this.ctx(u), id); }
  crear(u: JwtPayload, dto: CrearCitaDto) { return this.repo.crear(this.ctx(u), { ...dto }); }
  reprogramar(u: JwtPayload, id: string, dto: ReprogramarCitaDto) {
    return this.repo.reprogramar(this.ctx(u), id, dto.fecha_hora, dto.motivo, dto.veterinario_id);
  }
  cambiarEstado(u: JwtPayload, id: string, estado: string, motivo?: string) {
    return this.repo.cambiarEstado(this.ctx(u), id, estado, motivo);
  }
  eliminar(u: JwtPayload, id: string) { return this.repo.eliminar(this.ctx(u), id); }
}
