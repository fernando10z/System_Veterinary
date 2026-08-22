import { Injectable, Logger, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import Redis from "ioredis";

@Injectable()
export class RedisService implements OnModuleInit {
  private readonly logger = new Logger(RedisService.name);
  private client!: Redis;

  constructor(private readonly config: ConfigService) {}

  onModuleInit(): void {
    this.client = new Redis({
      host: this.config.get<string>("REDIS_HOST") ?? "localhost",
      port: Number(this.config.get<string>("REDIS_PORT") ?? 6382),
      password: this.config.get<string>("REDIS_PASSWORD") || undefined,
      db: Number(this.config.get<string>("REDIS_DB") ?? 0),
      keyPrefix: this.config.get<string>("REDIS_KEY_PREFIX") ?? "vet:",
      lazyConnect: false,
      maxRetriesPerRequest: 3,
    });
    this.client.on("error", (err) => this.logger.error(`Redis: ${err.message}`));
    this.client.on("connect", () => this.logger.log("Redis conectado"));
  }

  get raw(): Redis {
    return this.client;
  }

  async get<T = unknown>(key: string): Promise<T | null> {
    const v = await this.client.get(key);
    if (v === null) return null;
    try {
      return JSON.parse(v) as T;
    } catch {
      return v as unknown as T;
    }
  }

  async set(key: string, value: unknown, ttlSeconds?: number): Promise<void> {
    const v = typeof value === "string" ? value : JSON.stringify(value);
    if (ttlSeconds && ttlSeconds > 0) {
      await this.client.set(key, v, "EX", ttlSeconds);
    } else {
      await this.client.set(key, v);
    }
  }

  async del(...keys: string[]): Promise<void> {
    if (keys.length) await this.client.del(...keys);
  }

  async delPattern(pattern: string): Promise<number> {
    const prefix = this.config.get<string>("REDIS_KEY_PREFIX") ?? "vet:";
    const fullPattern = pattern.startsWith(prefix) ? pattern : `${prefix}${pattern}`;
    const stream = this.client.scanStream({ match: fullPattern, count: 100 });
    let deleted = 0;
    for await (const keys of stream) {
      if (keys.length) {
        const stripped = (keys as string[]).map((k) => (k.startsWith(prefix) ? k.slice(prefix.length) : k));
        await this.client.del(...stripped);
        deleted += keys.length;
      }
    }
    return deleted;
  }

  async wrap<T>(key: string, ttlSeconds: number, loader: () => Promise<T>): Promise<T> {
    const cached = await this.get<T>(key);
    if (cached !== null) return cached;
    const fresh = await loader();
    await this.set(key, fresh, ttlSeconds);
    return fresh;
  }

  async ping(): Promise<boolean> {
    try {
      const r = await this.client.ping();
      return r === "PONG";
    } catch {
      return false;
    }
  }

  async quit(): Promise<void> {
    try {
      await this.client.quit();
    } catch {
      this.client.disconnect();
    }
  }
}
