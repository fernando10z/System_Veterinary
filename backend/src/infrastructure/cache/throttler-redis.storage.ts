import { Injectable } from "@nestjs/common";
import { ThrottlerStorage } from "@nestjs/throttler";
import { ThrottlerStorageRecord } from "@nestjs/throttler/dist/throttler-storage-record.interface";
import { RedisService } from "./redis.service";

/**
 * Contador del límite de peticiones en Redis.
 *
 * El almacén por defecto de @nestjs/throttler vive en la memoria del proceso.
 * En producción PM2 arranca en modo cluster con `instances: "max"`, así que
 * cada núcleo llevaba su propia cuenta: el límite de 10 intentos de login por
 * minuto se multiplicaba por el número de núcleos, y qué límite real tenía la
 * clínica dependía del servidor donde se desplegara.
 *
 * Si Redis no responde, el error se propaga: decide ThrottlerVetGuard. Las
 * rutas de credenciales fallan cerradas (503) y el resto se deja pasar —dejar
 * la clínica sin sistema por un hipo de Redis es peor que perder el límite por
 * IP un rato—. Antes se tragaba aquí y el login quedaba sin límite.
 */
@Injectable()
export class ThrottlerRedisStorage implements ThrottlerStorage {
  constructor(private readonly redis: RedisService) {}

  async increment(
    key: string,
    ttl: number,
    limit: number,
    blockDuration: number,
    throttlerName: string,
  ): Promise<ThrottlerStorageRecord> {
    const contador = `thr:${throttlerName}:${key}`;
    const bloqueo = `${contador}:b`;

    const r = this.redis.raw;

    const bloqueoMs = await r.pttl(bloqueo);
    if (bloqueoMs > 0) {
      return {
        totalHits: limit + 1,
        timeToExpire: 0,
        isBlocked: true,
        timeToBlockExpire: Math.ceil(bloqueoMs / 1000),
      };
    }

    const [[, hits]] = (await r
      .multi()
      .incr(contador)
      .pexpire(contador, ttl, "NX")
      .exec()) as [[Error | null, number], ...unknown[]];

    const restanteMs = await r.pttl(contador);
    const restante = Math.ceil(Math.max(restanteMs, 0) / 1000);

    if (hits > limit) {
      const castigo = blockDuration > 0 ? blockDuration : ttl;
      await r.set(bloqueo, "1", "PX", castigo);
      return {
        totalHits: hits,
        timeToExpire: restante,
        isBlocked: true,
        timeToBlockExpire: Math.ceil(castigo / 1000),
      };
    }

    return { totalHits: hits, timeToExpire: restante, isBlocked: false, timeToBlockExpire: 0 };
  }
}
