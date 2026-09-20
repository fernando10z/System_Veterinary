import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import { JwtService } from "@nestjs/jwt";
import { ConfigService } from "@nestjs/config";
import { IS_PUBLIC_KEY } from "../decorators/public.decorator";
import { AuthenticatedRequest } from "../types/authenticated-request.type";
import { JwtPayload } from "../types/jwt-payload.type";

/**
 * Lo único que se puede hacer con una clave temporal sin estrenar: consultar
 * quién eres, cambiarla o salir.
 */
const RUTAS_CON_CLAVE_TEMPORAL = new Set([
  "/api/auth/cambiar-password",
  "/api/auth/perfil",
  "/api/auth/logout",
]);

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (isPublic) return true;

    const req = ctx.switchToHttp().getRequest<AuthenticatedRequest>();
    const auth = req.headers["authorization"];
    if (!auth || typeof auth !== "string" || !auth.startsWith("Bearer ")) {
      throw new UnauthorizedException("Falta token de acceso");
    }
    const token = auth.slice("Bearer ".length).trim();

    let payload: JwtPayload;
    try {
      payload = await this.jwt.verifyAsync<JwtPayload>(token, {
        secret: this.config.get<string>("JWT_ACCESS_SECRET"),
        issuer: this.config.get<string>("JWT_ISSUER"),
        audience: this.config.get<string>("JWT_AUDIENCE"),
      });
    } catch {
      throw new UnauthorizedException("Token inválido o expirado");
    }
    req.user = payload;

    // El administrador crea al usuario con una clave temporal y
    // `must_change_password`. El dato se guardaba, se devolvía en el login y no
    // lo exigía nadie: esa clave —la que se dicta por teléfono— seguía sirviendo
    // indefinidamente.
    //
    // La comprobación va FUERA del try: dentro, el catch la convertía en un
    // "token inválido" y el usuario no sabría qué hacer para salir del bucle.
    if (payload.must_change_password === true) {
      const ruta = (req.url ?? "").split("?")[0];
      if (!RUTAS_CON_CLAVE_TEMPORAL.has(ruta)) {
        throw new ForbiddenException({
          code: "PASSWORD_CHANGE_REQUIRED",
          message: "Debes cambiar tu contraseña temporal antes de continuar",
        });
      }
    }
    return true;
  }
}
