import { Injectable } from "@nestjs/common";
import { PortalRepository } from "./portal.repository";

@Injectable()
export class PortalService {
  constructor(private readonly repo: PortalRepository) {}

  misMascotas(clienteId: string) { return this.repo.misMascotas(clienteId); }
  misCitas(clienteId: string, incluirPasadas: boolean) {
    return this.repo.misCitas(clienteId, incluirPasadas);
  }
  historial(clienteId: string, mascotaId: string) {
    return this.repo.historial(clienteId, mascotaId);
  }
  misComprobantes(clienteId: string) { return this.repo.misComprobantes(clienteId); }
  solicitarCita(clienteId: string, dto: object) {
    return this.repo.solicitarCita(clienteId, { ...dto });
  }
  cambiarPassword(clienteId: string, actual: string, nueva: string) {
    return this.repo.cambiarPassword(clienteId, actual, nueva);
  }
}
