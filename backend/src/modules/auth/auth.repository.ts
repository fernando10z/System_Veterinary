import { Injectable } from "@nestjs/common";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";
import { SpContext } from "../../common/types/sp-result.type";

/**
 * Toda la validación de credenciales ocurre en la base (pgcrypto crypt()).
 * El backend nunca ve ni compara hashes: solo orquesta.
 */
@Injectable()
export class AuthRepository {
  constructor(private readonly sp: SpExecutorService) {}

  login(email: string, password: string) {
    return this.sp.call<LoginData>("app.sp_auth_login", [email, password]);
  }

  perfil(userId: string) {
    return this.sp.call<LoginData>("app.fn_auth_perfil", [userId]);
  }

  cambiarPassword(ctx: SpContext, actual: string, nueva: string) {
    return this.sp.callCtx("app.sp_auth_cambiar_password", ctx, [actual, nueva]);
  }

  solicitarReset(email: string) {
    return this.sp.call<{ enviado: boolean; token: string | null; email?: string }>(
      "app.sp_auth_solicitar_reset", [email]);
  }

  resetPassword(token: string, nueva: string) {
    return this.sp.call("app.sp_auth_reset_password", [token, nueva]);
  }

  portalLogin(documento: string, password: string) {
    return this.sp.call<{ cliente: PortalCliente }>("app.sp_portal_login", [documento, password]);
  }
}

export interface LoginData {
  user: {
    id: string;
    email: string;
    codigo: string | null;
    nombres: string;
    apellido_paterno: string;
    apellido_materno: string | null;
    telefono: string | null;
    foto_url: string | null;
    is_super_admin: boolean;
    empresa_id: string | null;
    es_veterinario: boolean;
    colegiatura: string | null;
    must_change_password: boolean;
  };
  rol: { id: string; codigo: string; nombre: string; scope: string } | null;
  permisos: string[];
  empresa: Record<string, unknown> | null;
}

export interface PortalCliente {
  id: string;
  codigo: string | null;
  nombres: string;
  apellido_paterno: string | null;
  correo: string | null;
  telefono: string | null;
}
