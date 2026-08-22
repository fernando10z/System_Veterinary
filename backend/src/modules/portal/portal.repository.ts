import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { jsonbArg } from "../../infrastructure/database/sp-args";

/**
 * Los SPs del portal reciben `cliente_id` (del JWT type=portal), nunca un
 * user_id de staff: todo lo que devuelven está acotado a ese propietario.
 */
@Injectable()
export class PortalRepository {
  constructor(private readonly sp: SpExecutorService) {}

  misMascotas(clienteId: string) {
    return this.sp.call<unknown[]>("app.fn_portal_mis_mascotas", [clienteId]);
  }
  misCitas(clienteId: string, incluirPasadas: boolean) {
    return this.sp.call<unknown[]>("app.fn_portal_mis_citas", [clienteId, incluirPasadas]);
  }
  historial(clienteId: string, mascotaId: string) {
    return this.sp.call("app.fn_portal_historial", [clienteId, mascotaId]);
  }
  misComprobantes(clienteId: string) {
    return this.sp.call<unknown[]>("app.fn_portal_mis_comprobantes", [clienteId]);
  }
  solicitarCita(clienteId: string, payload: Record<string, unknown>) {
    return this.sp.call("app.sp_portal_solicitar_cita", [clienteId, jsonbArg(payload)]);
  }
  cambiarPassword(clienteId: string, actual: string, nueva: string) {
    return this.sp.call("app.sp_portal_cambiar_password", [clienteId, actual, nueva]);
  }
}
