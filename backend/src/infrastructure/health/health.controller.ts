import { Controller, Get, Inject } from "@nestjs/common";
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

  @Public()
  @Get()
  async check() {
    const [db, redis, minio] = await Promise.all([
      this.pingDb(),
      this.redis.ping(),
      this.minio.ping(),
    ]);
    const ok = db && redis && minio;
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
