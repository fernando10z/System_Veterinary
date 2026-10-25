import { Injectable, UnauthorizedException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { AuthRepository, LoginData } from "./auth.repository";
import { SesionesService, duracionEnSegundos } from "../../infrastructure/cache/sesiones.service";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

@Injectable()
export class AuthService {
  constructor(
    private readonly repo: AuthRepository,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly sesiones: SesionesService,
  ) {}

  // Sin JWT_ISSUER/JWT_AUDIENCE en el entorno, jsonwebtoken rechaza firmar
  // ("issuer must be a string") y el login entero respondía 500: el compose
  // de producción no las definía. Van con el mismo default que jwt.config.ts.

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  async login(email: string, password: string) {
    const data = await this.repo.login(email, password);
    return this.emitirSesion(data);
  }

  /**
   * Firma el par access/refresh y deja el refresh en la whitelist de Redis.
   * La whitelist es lo que permite revocar una sesión concreta (logout, cambio
   * de rol) sin esperar a que expire el token.
   */
  private async emitirSesion(data: LoginData) {
    const payload: JwtPayload = {
      sub: data.user.id,
      email: data.user.email,
      empresa_id: data.user.empresa_id,
      is_super_admin: data.user.is_super_admin,
      roles: data.rol ? [data.rol.codigo] : [],
      must_change_password: data.user.must_change_password === true,
    };

    const jti = randomUUID();
    const access_token = await this.jwt.signAsync(payload, {
      secret: this.config.get<string>("JWT_ACCESS_SECRET"),
      expiresIn: this.config.get<string>("JWT_ACCESS_EXPIRES") ?? "15m",
      issuer: this.config.get<string>("JWT_ISSUER") ?? "veterp",
      audience: this.config.get<string>("JWT_AUDIENCE") ?? "veterp-backoffice",
    });

    const refreshExpires = this.config.get<string>("JWT_REFRESH_EXPIRES") ?? "7d";
    const refresh_token = await this.jwt.signAsync(
      { sub: data.user.id, jti },
      {
        secret: this.config.get<string>("JWT_REFRESH_SECRET"),
        expiresIn: refreshExpires,
        issuer: this.config.get<string>("JWT_ISSUER") ?? "veterp",
        audience: this.config.get<string>("JWT_AUDIENCE") ?? "veterp-backoffice",
      },
    );

    // La entrada de Redis vence con el token: ni antes (cerraría sesiones
    // válidas) ni después (guardaría sesiones que ya nadie puede usar).
    await this.sesiones.registrar(jti, data.user.id, duracionEnSegundos(refreshExpires));

    return { access_token, refresh_token, ...data };
  }

  async refresh(refresh_token: string) {
    let decoded: { sub: string; jti: string };
    try {
      decoded = await this.jwt.verifyAsync(refresh_token, {
        secret: this.config.get<string>("JWT_REFRESH_SECRET"),
        issuer: this.config.get<string>("JWT_ISSUER") ?? "veterp",
        audience: this.config.get<string>("JWT_AUDIENCE") ?? "veterp-backoffice",
      });
    } catch {
      throw new UnauthorizedException("Sesión expirada, vuelve a iniciar sesión");
    }

    // Rotación atómica: el refresh se consume (se lee y se borra) en una sola
    // operación. Si no estaba —revocado, vencido o ya usado— no hay sesión.
    const titular = decoded.jti ? await this.sesiones.consumir(decoded.jti) : null;
    if (!titular || titular !== decoded.sub) {
      throw new UnauthorizedException("Sesión revocada, vuelve a iniciar sesión");
    }

    // fn_auth_perfil rechaza a una cuenta que ya no está activa: la baja corta
    // también la renovación, no solo el siguiente login.
    const data = await this.repo.perfil(decoded.sub);
    return this.emitirSesion(data);
  }

  async logout(refresh_token?: string) {
    if (!refresh_token) return { cerrado: true };
    try {
      const decoded = await this.jwt.verifyAsync<{ jti: string }>(refresh_token, {
        secret: this.config.get<string>("JWT_REFRESH_SECRET"),
        issuer: this.config.get<string>("JWT_ISSUER") ?? "veterp",
        audience: this.config.get<string>("JWT_AUDIENCE") ?? "veterp-backoffice",
      });
      await this.sesiones.revocar(decoded.jti);
    } catch {
      // Un token ya vencido o inválido no impide cerrar sesión.
    }
    return { cerrado: true };
  }

  perfil(userId: string) {
    return this.repo.perfil(userId);
  }

  /**
   * Cambiar la contraseña cierra todas las sesiones abiertas del usuario: si
   * la cambió porque sospechaba que alguien más la tenía, esa otra sesión es
   * justo la que hay que cortar. A quien la cambió se le entrega un par nuevo
   * —ya sin `must_change_password`— para que no tenga que volver a entrar.
   */
  async cambiarPassword(u: JwtPayload, actual: string, nueva: string) {
    await this.repo.cambiarPassword(this.ctx(u), actual, nueva);
    await this.sesiones.revocarTodas(u.sub);
    const sesion = await this.emitirSesion(await this.repo.perfil(u.sub));
    return {
      updated: true,
      access_token: sesion.access_token,
      refresh_token: sesion.refresh_token,
    };
  }

  solicitarReset(email: string) {
    return this.repo.solicitarReset(email);
  }

  async resetPassword(token: string, nueva: string) {
    const data = await this.repo.resetPassword(token, nueva);
    if (data?.user_id) await this.sesiones.revocarTodas(data.user_id);
    return { updated: true };
  }

  /**
   * Token del portal: issuer/audience propios y `type: "portal"`. El guard del
   * backoffice valida contra el otro issuer, así que este token no le sirve.
   */
  async portalLogin(documento: string, password: string) {
    const data = await this.repo.portalLogin(documento, password);
    const access_token = await this.jwt.signAsync(
      { sub: data.cliente.id, type: "portal", email: data.cliente.correo ?? "" },
      {
        secret: this.config.get<string>("JWT_ACCESS_SECRET"),
        expiresIn: this.config.get<string>("JWT_PORTAL_EXPIRES") ?? "8h",
        issuer: this.config.get<string>("JWT_PORTAL_ISSUER") ?? "veterp-portal",
        audience: this.config.get<string>("JWT_PORTAL_AUDIENCE") ?? "veterp-clientes",
      },
    );
    return { access_token, cliente: data.cliente };
  }
}
