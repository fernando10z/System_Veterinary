import { Global, Module, OnApplicationShutdown, Inject } from "@nestjs/common";
import { ConfigModule, ConfigService } from "@nestjs/config";
import { Pool } from "pg";
import { SpExecutorService } from "./sp-executor.service";
import { PG_POOL } from "./database.constants";

@Global()
@Module({
  imports: [ConfigModule],
  providers: [
    {
      provide: PG_POOL,
      inject: [ConfigService],
      useFactory: (config: ConfigService) =>
        new Pool({
          connectionString: config.get<string>("DATABASE_URL"),
          min: Number(config.get<string>("DATABASE_POOL_MIN") ?? 2),
          max: Number(config.get<string>("DATABASE_POOL_MAX") ?? 10),
          ssl:
            config.get<string>("DATABASE_SSL") === "true"
              ? { rejectUnauthorized: false }
              : false,
        }),
    },
    SpExecutorService,
  ],
  exports: [PG_POOL, SpExecutorService],
})
export class DatabaseModule implements OnApplicationShutdown {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  async onApplicationShutdown(): Promise<void> {
    await this.pool.end();
  }
}
