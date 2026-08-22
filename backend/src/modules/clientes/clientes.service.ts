import { Injectable } from "@nestjs/common";
import { ClientesRepository } from "./clientes.repository";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";
import { CrearClienteDto } from "./dto/crear-cliente.dto";
import { ActualizarClienteDto } from "./dto/actualizar-cliente.dto";
import { RegistrarComunicacionDto } from "./dto/registrar-comunicacion.dto";

@Injectable()
export class ClientesService {
  constructor(private readonly repo: ClientesRepository) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  listar(u: JwtPayload, filtros: Record<string, unknown>, page: number, pageSize: number) {
    return this.repo.listar(this.ctx(u), filtros, page, pageSize);
  }
  obtener(u: JwtPayload, id: string) { return this.repo.obtener(this.ctx(u), id); }
  buscar(u: JwtPayload, q: string, limit: number) { return this.repo.buscar(this.ctx(u), q, limit); }
  crear(u: JwtPayload, dto: CrearClienteDto) { return this.repo.crear(this.ctx(u), { ...dto }); }
  actualizar(u: JwtPayload, id: string, dto: ActualizarClienteDto) {
    return this.repo.actualizar(this.ctx(u), id, { ...dto });
  }
  activarPortal(u: JwtPayload, id: string, password: string) {
    return this.repo.activarPortal(this.ctx(u), id, password);
  }
  eliminar(u: JwtPayload, id: string) { return this.repo.eliminar(this.ctx(u), id); }
  comunicaciones(u: JwtPayload, clienteId: string | null, limit: number) {
    return this.repo.comunicaciones(this.ctx(u), clienteId, limit);
  }
  registrarComunicacion(u: JwtPayload, dto: RegistrarComunicacionDto) {
    return this.repo.registrarComunicacion(this.ctx(u), { ...dto });
  }
}
