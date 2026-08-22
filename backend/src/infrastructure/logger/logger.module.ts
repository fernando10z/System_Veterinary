import { Module } from "@nestjs/common";
import { LoggerModule as PinoLoggerModule } from "nestjs-pino";
import { ConfigModule, ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";

@Module({
  imports: [
    PinoLoggerModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        pinoHttp: {
          level: config.get<string>("LOG_LEVEL") ?? "info",
          genReqId: (req: any) => (req.headers["x-request-id"] as string) || randomUUID(),
          customProps: (req: any) => ({
            userId: req.user?.sub,
            empresaId: req.user?.empresa_id,
          }),
          serializers: {
            req: (req: any) => ({
              id: req.id,
              method: req.method,
              url: req.url,
            }),
            res: (res: any) => ({ statusCode: res.statusCode }),
          },
          transport:
            config.get<string>("LOG_PRETTY") === "true"
              ? {
                  target: "pino-pretty",
                  options: { singleLine: true, colorize: true, translateTime: "SYS:HH:MM:ss" },
                }
              : undefined,
        },
      }),
    }),
  ],
  exports: [PinoLoggerModule],
})
export class LoggerModule {}
