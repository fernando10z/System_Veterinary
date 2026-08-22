import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { ConfigService } from "@nestjs/config";
import { FastifyRequest } from "fastify";

export interface PortalPayload {
  sub: string;          // cliente_id
  type: "portal";
  email?: string;
}

/**
 * Guard del portal del propietario. Verifica contra el issuer/audience del
 * portal y exige `type === "portal"`: un token del backoffice no pasa por aquí,
 * ni uno del portal pasa por el guard del staff.
 */
@Injectable()
export class PortalAuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<FastifyRequest & { cliente?: PortalPayload }>();
    const auth = req.headers["authorization"];
    if (!auth || typeof auth !== "string" || !auth.startsWith("Bearer ")) {
      throw new UnauthorizedException("Falta token de acceso");
    }
    try {
      const payload = await this.jwt.verifyAsync<PortalPayload>(
        auth.slice("Bearer ".length).trim(),
        {
          secret: this.config.get<string>("JWT_ACCESS_SECRET"),
          issuer: this.config.get<string>("JWT_PORTAL_ISSUER") ?? "veterp-portal",
          audience: this.config.get<string>("JWT_PORTAL_AUDIENCE") ?? "veterp-clientes",
        },
      );
      if (payload.type !== "portal") {
        throw new UnauthorizedException("Token no válido para el portal");
      }
      req.cliente = payload;
      return true;
    } catch {
      throw new UnauthorizedException("Token inválido o expirado");
    }
  }
}
