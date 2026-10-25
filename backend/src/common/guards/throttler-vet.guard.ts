import { ExecutionContext, Injectable, Logger, ServiceUnavailableException } from "@nestjs/common";
import { ThrottlerException, ThrottlerGuard } from "@nestjs/throttler";
import { FALLA_CERRADO_KEY } from "../decorators/limite-credenciales.decorator";

/**
 * ThrottlerGuard con una decisión explícita para cuando el contador (Redis)
 * no responde:
 *  - rutas con @LimiteCredenciales(): se rechaza con 503. Sin contador, el
 *    login quedaría abierto a fuerza bruta a velocidad de red.
 *  - el resto: se deja pasar y se registra.
 */
@Injectable()
export class ThrottlerVetGuard extends ThrottlerGuard {
  private readonly log = new Logger(ThrottlerVetGuard.name);

  async canActivate(context: ExecutionContext): Promise<boolean> {
    try {
      return await super.canActivate(context);
    } catch (err) {
      if (err instanceof ThrottlerException) throw err;
      const fallaCerrado = this.reflector.getAllAndOverride<boolean>(FALLA_CERRADO_KEY, [
        context.getHandler(),
        context.getClass(),
      ]);
      this.log.warn(
        `Sin contador de peticiones (${(err as Error)?.message ?? err}); ` +
          (fallaCerrado ? "ruta de credenciales: se rechaza" : "se deja pasar"),
      );
      if (fallaCerrado) {
        throw new ServiceUnavailableException({
          code: "SERVICE_UNAVAILABLE",
          message: "El servicio de acceso no está disponible. Intenta en unos minutos.",
        });
      }
      return true;
    }
  }
}
