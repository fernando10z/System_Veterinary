import { Controller, Get, Inject, Res } from "@nestjs/common";
import { FastifyReply } from "fastify";
import { Pool } from "pg";
import { Public } from "../../common/decorators/public.decorator";
import { PG_POOL } from "../database/database.constants";
import { RedisService } from "../cache/redis.service";
import { MinioService } from "../storage/minio.service";

@Controller("health")
export class HealthController {
  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly redis: RedisService,
    private readonly minio: MinioService,
  ) {}

  /**
   * 200 si responden la base, Redis y MinIO; 503 si falla cualquiera. El
   * código importa más que el cuerpo: el healthcheck del compose, el
   * balanceador y el monitoreo miran el status, y con un 200 fijo un backend
   * sin base seguía pareciendo sano.
   */
  @Public()
  @Get()
  async check(@Res({ passthrough: true }) reply: FastifyReply) {
    const [db, redis, minio] = await Promise.all([
      conTope(this.pingDb()),
      conTope(this.redis.ping()),
      conTope(this.minio.ping()),
    ]);
    const ok = db && redis && minio;
    reply.status(ok ? 200 : 503);
    return {
      ok,
      data: { db, redis, minio, uptime: Math.round(process.uptime()) },
    };
  }

  private async pingDb(): Promise<boolean> {
    try {
      const r = await this.pool.query("SELECT 1 AS ok");
      return r.rows[0]?.ok === 1;
    } catch {
      return false;
    }
  }
}

/** Un servicio que no contesta en 3 s cuenta como caído: el healthcheck no puede colgarse. */
function conTope(p: Promise<boolean>, ms = 3000): Promise<boolean> {
  return Promise.race([
    p.catch(() => false),
    new Promise<boolean>((resolve) => setTimeout(() => resolve(false), ms).unref()),
  ]);
}
