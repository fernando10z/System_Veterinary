import { Injectable } from "@nestjs/common";
import { RedisService } from "./redis.service";

/** Clave de un refresh token vigente: su jti → id del usuario. */
export const CLAVE_REFRESH = (jti: string) => `refresh:${jti}`;
/** Índice por usuario: los jti de todas sus sesiones abiertas. */
export const CLAVE_SESIONES_USUARIO = (userId: string) => `refresh:user:${userId}`;

/**
 * Whitelist de refresh tokens en Redis.
 *
 * Cada sesión es una clave `refresh:<jti>` con el id del usuario. Además, por
 * usuario, un set con los jti de sus sesiones abiertas: sin él, cambiar la
 * contraseña o dar de baja una cuenta no podía cerrar las sesiones que ya
 * estaban abiertas —el refresh seguía renovando el acceso durante 7 días—.
 */
@Injectable()
export class SesionesService {
  constructor(private readonly redis: RedisService) {}

  async registrar(jti: string, userId: string, ttlSegundos: number): Promise<void> {
    const ttl = Math.max(1, Math.floor(ttlSegundos));
    const indice = CLAVE_SESIONES_USUARIO(userId);
    const r = await this.redis.raw
      .multi()
      .set(CLAVE_REFRESH(jti), userId, "EX", ttl)
      .sadd(indice, jti)
      // El índice vive lo que la sesión más nueva: cada login lo renueva.
      .expire(indice, ttl)
      .exec();
    const fallo = r?.find(([err]) => err);
    if (fallo) throw fallo[0];
  }

  /**
   * Consume la sesión: la lee y la borra en UNA operación (GETDEL). Con un GET
   * seguido de un DEL, dos peticiones con el mismo refresh que llegaran a la
   * vez leían las dos "vigente" antes de que ninguna borrara, y el token
   * robado seguía rotando junto al legítimo. Devuelve el id del usuario, o
   * null si la sesión no existe (vencida, revocada o ya usada).
   */
  async consumir(jti: string): Promise<string | null> {
    const userId = await this.redis.raw.getdel(CLAVE_REFRESH(jti));
    if (userId) await this.redis.raw.srem(CLAVE_SESIONES_USUARIO(userId), jti);
    return userId;
  }

  /** Cierra una sesión concreta (logout). */
  async revocar(jti: string): Promise<void> {
    await this.consumir(jti);
  }

  /**
   * Cierra TODAS las sesiones del usuario: cambio o reseteo de contraseña,
   * baja, suspensión, cambio de rol. El access token vigente dura como mucho
   * 15 minutos más, y `assert_permiso` ya rechaza a una cuenta inactiva.
   */
  async revocarTodas(userId: string): Promise<number> {
    const indice = CLAVE_SESIONES_USUARIO(userId);
    const jtis = await this.redis.raw.smembers(indice);
    const claves = [...jtis.map(CLAVE_REFRESH), indice];
    await this.redis.raw.del(...claves);
    return jtis.length;
  }
}

/**
 * Convierte la duración de JWT_REFRESH_EXPIRES a segundos, con la misma
 * sintaxis que acepta jsonwebtoken: un número (segundos) o "30m", "12h",
 * "7d", "2w". Así la sesión en Redis vence cuando vence el token, y no a los
 * 7 días fijos que había escritos a mano.
 */
export function duracionEnSegundos(valor: string | number | undefined, porDefecto = 7 * 24 * 3600): number {
  if (valor === undefined || valor === null || valor === "") return porDefecto;
  if (typeof valor === "number") return valor;
  const m = /^\s*(\d+(?:\.\d+)?)\s*(ms|s|m|h|d|w|y)?\s*$/i.exec(valor);
  if (!m) return porDefecto;
  const n = Number(m[1]);
  const factor: Record<string, number> = {
    ms: 0.001, s: 1, m: 60, h: 3600, d: 86400, w: 604800, y: 31557600,
  };
  return Math.ceil(n * factor[(m[2] ?? "s").toLowerCase()]);
}
