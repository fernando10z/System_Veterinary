import { Global, Module, OnApplicationShutdown } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { RedisService } from "./redis.service";
import { SesionesService } from "./sesiones.service";

@Global()
@Module({
  imports: [ConfigModule],
  providers: [RedisService, SesionesService],
  exports: [RedisService, SesionesService],
})
export class CacheModule implements OnApplicationShutdown {
  constructor(private readonly redis: RedisService) {}

  async onApplicationShutdown(): Promise<void> {
    await this.redis.quit();
  }
}
