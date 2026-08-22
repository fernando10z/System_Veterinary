import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { FastifyAdapter, NestFastifyApplication } from "@nestjs/platform-fastify";
import { BadRequestException, ValidationPipe } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Logger as PinoLogger } from "nestjs-pino";
import fastifyCookie from "@fastify/cookie";
import fastifyMultipart from "@fastify/multipart";
import fastifyCors from "@fastify/cors";
import fastifyHelmet from "@fastify/helmet";
import { AppModule } from "./app.module";
import { mensajesValidacionES } from "./common/validation-messages";

async function bootstrap() {
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter({
      logger: false,
      trustProxy: true,
      // Radiografías y ecografías pesan: 50 MB cubre el caso real.
      bodyLimit: 50 * 1024 * 1024,
    }),
    // bodyParser: false → registramos nosotros el parser JSON más abajo. El de
    // Nest no admite cuerpo vacío y no se puede reemplazar una vez montado.
    { bufferLogs: true, bodyParser: false },
  );

  app.useLogger(app.get(PinoLogger));
  const config = app.get(ConfigService);

  // Parser JSON propio. El de Nest responde 500 cuando el cliente manda
  // Content-Type: application/json con el cuerpo vacío, y varias acciones del
  // ERP son PATCH/POST sin cuerpo (cerrar consulta, marcar notificación leída,
  // marcar asistencia). Aquí un cuerpo vacío se interpreta como {}.
  const fastify = app.getHttpAdapter().getInstance();
  fastify.addContentTypeParser(
    "application/json",
    { parseAs: "string" },
    (_req: unknown, body: string, done: (err: Error | null, result?: unknown) => void) => {
      if (!body || body.trim() === "") return done(null, {});
      try {
        done(null, JSON.parse(body));
      } catch {
        done(new BadRequestException({
          code: "BAD_REQUEST",
          message: "El cuerpo de la petición no es JSON válido",
        }));
      }
    },
  );
  fastify.addContentTypeParser(
    "application/x-www-form-urlencoded",
    { parseAs: "string" },
    (_req: unknown, body: string, done: (err: Error | null, result?: unknown) => void) => {
      done(null, Object.fromEntries(new URLSearchParams(body ?? "")));
    },
  );

  await app.register(fastifyHelmet as any, {
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: { policy: "cross-origin" },
  });
  await app.register(fastifyCookie as any, {
    secret: config.get<string>("COOKIE_SECRET"),
  });
  await app.register(fastifyMultipart as any, {
    limits: { fileSize: 50 * 1024 * 1024 },
  });
  await app.register(fastifyCors as any, {
    origin: (config.get<string>("CORS_ORIGINS") ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
    credentials: true,
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: false,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
      // Mensajes en español: el usuario final es personal de clínica, no dev.
      exceptionFactory: (errors) => {
        const mensajes = mensajesValidacionES(errors);
        return new BadRequestException({
          code: "VALIDATION_ERROR",
          message: mensajes[0] ?? "Hay datos inválidos en el formulario",
          detail: mensajes,
        });
      },
    }),
  );

  app.setGlobalPrefix("api");
  app.enableShutdownHooks();

  const port = Number(config.get<string>("PORT") ?? 3100);
  await app.listen(port, "0.0.0.0");

  app.get(PinoLogger).log(`ERP Veterinario listo en http://localhost:${port}/api`);
}

bootstrap();
