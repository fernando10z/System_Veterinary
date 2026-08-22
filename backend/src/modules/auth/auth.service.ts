import { Injectable, UnauthorizedException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { AuthRepository, LoginData } from "./auth.repository";
import { RedisService } from "../../infrastructure/cache/redis.service";
import { JwtPayload } from "../../common/types/jwt-payload.type";
import { SpContext } from "../../common/types/sp-result.type";

/** Prefijo de la whitelist de refresh tokens en Redis. */
const REFRESH_KEY = (jti: string) => `refresh:${jti}`;

@Injectable()
export class AuthService {
  constructor(
    private readonly repo: AuthRepository,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly redis: RedisService,
  ) {}

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
    };

    const jti = randomUUID();
    const accessToken = await this.jwt.signAsync(payload, {
      secret: this.config.get<string>("JWT_ACCESS_SECRET"),
      expiresIn: this.config.get<string>("JWT_ACCESS_EXPIRES") ?? "15m",
      issuer: this.config.get<string>("JWT_ISSUER"),
      audience: this.config.get<string>("JWT_AUDIENCE"),
    });

    const refreshToken = await this.jwt.signAsync(
      { sub: data.user.id, jti },
      {
        secret: this.config.get<string>("JWT_REFRESH_SECRET"),
        expiresIn: this.config.get<string>("JWT_REFRESH_EXPIRES") ?? "7d",
        issuer: this.config.get<string>("JWT_ISSUER"),
        audience: this.config.get<string>("JWT_AUDIENCE"),
      },
    );

    await this.redis.set(REFRESH_KEY(jti), data.user.id, 7 * 24 * 3600);

    return { accessToken, refreshToken, ...data };
  }

  async refresh(refreshToken: string) {
    let decoded: { sub: string; jti: string };
    try {
      decoded = await this.jwt.verifyAsync(refreshToken, {
        secret: this.config.get<string>("JWT_REFRESH_SECRET"),
        issuer: this.config.get<string>("JWT_ISSUER"),
        audience: this.config.get<string>("JWT_AUDIENCE"),
      });
    } catch {
      throw new UnauthorizedException("Sesión expirada, vuelve a iniciar sesión");
    }

    // Si el jti no está en la whitelist, la sesión fue revocada.
    const vigente = await this.redis.get(REFRESH_KEY(decoded.jti));
    if (!vigente) {
      throw new UnauthorizedException("Sesión revocada, vuelve a iniciar sesión");
    }

    // Rotación: el refresh usado se invalida al emitir el nuevo par.
    await this.redis.del(REFRESH_KEY(decoded.jti));

    const data = await this.repo.perfil(decoded.sub);
    return this.emitirSesion(data);
  }

  async logout(refreshToken?: string) {
    if (!refreshToken) return { cerrado: true };
    try {
      const decoded = await this.jwt.verifyAsync<{ jti: string }>(refreshToken, {
        secret: this.config.get<string>("JWT_REFRESH_SECRET"),
        issuer: this.config.get<string>("JWT_ISSUER"),
        audience: this.config.get<string>("JWT_AUDIENCE"),
      });
      await this.redis.del(REFRESH_KEY(decoded.jti));
    } catch {
      // Un token ya vencido o inválido no impide cerrar sesión.
    }
    return { cerrado: true };
  }

  perfil(userId: string) {
    return this.repo.perfil(userId);
  }

  cambiarPassword(u: JwtPayload, actual: string, nueva: string) {
    return this.repo.cambiarPassword(this.ctx(u), actual, nueva);
  }

  solicitarReset(email: string) {
    return this.repo.solicitarReset(email);
  }

  resetPassword(token: string, nueva: string) {
    return this.repo.resetPassword(token, nueva);
  }

  /**
   * Token del portal: issuer/audience propios y `type: "portal"`. El guard del
   * backoffice valida contra el otro issuer, así que este token no le sirve.
   */
  async portalLogin(documento: string, password: string) {
    const data = await this.repo.portalLogin(documento, password);
    const accessToken = await this.jwt.signAsync(
      { sub: data.cliente.id, type: "portal", email: data.cliente.correo ?? "" },
      {
        secret: this.config.get<string>("JWT_ACCESS_SECRET"),
        expiresIn: this.config.get<string>("JWT_PORTAL_EXPIRES") ?? "8h",
        issuer: this.config.get<string>("JWT_PORTAL_ISSUER") ?? "veterp-portal",
        audience: this.config.get<string>("JWT_PORTAL_AUDIENCE") ?? "veterp-clientes",
      },
    );
    return { accessToken, cliente: data.cliente };
  }
}
