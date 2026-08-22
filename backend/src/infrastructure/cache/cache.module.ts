import { Global, Module, OnApplicationShutdown } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { RedisService } from "./redis.service";

@Global()
@Module({
  imports: [ConfigModule],
  providers: [RedisService],
  exports: [RedisService],
})
export class CacheModule implements OnApplicationShutdown {
  constructor(private readonly redis: RedisService) {}

  async onApplicationShutdown(): Promise<void> {
    await this.redis.quit();
  }
}
