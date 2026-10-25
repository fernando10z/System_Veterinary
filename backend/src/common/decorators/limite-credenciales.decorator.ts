import { SetMetadata, applyDecorators } from "@nestjs/common";
import { Throttle } from "@nestjs/throttler";

export const FALLA_CERRADO_KEY = "throttleFallaCerrado";

/**
 * Límite estrecho para los endpoints que aceptan credenciales (login, reset,
 * portal). El global (200/min) sirve para la operación normal, pero deja
 * espacio de sobra para probar contraseñas.
 *
 * Además marca la ruta como "falla cerrado": si Redis no responde y no hay con
 * qué contar los intentos, la petición se rechaza (503) en vez de dejarla
 * pasar sin límite. En el resto de rutas se deja pasar: dejar a la clínica sin
 * agenda por un hipo de Redis es peor que perder el límite por IP un rato.
 */
export const LimiteCredenciales = () =>
  applyDecorators(
    Throttle({ default: { limit: 10, ttl: 60_000 } }),
    SetMetadata(FALLA_CERRADO_KEY, true),
  );
