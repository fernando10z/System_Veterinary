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
import { SanearEntradaPipe } from "./common/pipes/sanear-entrada.pipe";
import { iniciarContexto } from "./common/context/request-context";

/**
 * Cuántos saltos de proxy son de confianza. Fastify acepta un número (saltos),
 * una lista de IPs/CIDR o false. Por defecto: ninguno.
 */
function resolverTrustProxy(valor?: string): boolean | number | string {
  const v = (valor ?? "").trim();
  if (v === "" || v === "false" || v === "0") return false;
  if (/^\d+$/.test(v)) return Number(v);
  return v; // IPs o CIDR separados por coma
}

async function bootstrap() {
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter({
      logger: false,
      // `true` significaba "confía en cualquier X-Forwarded-For", incluida la
      // que escriba el cliente. Con eso, el límite de intentos de login se
      // saltaba cambiando una cabecera y la IP de la bitácora era la que el
      // atacante quisiera. Ahora se declara cuántos proxies hay delante:
      // TRUST_PROXY=1 detrás del nginx del despliegue, vacío si no hay ninguno.
      trustProxy: resolverTrustProxy(process.env.TRUST_PROXY),
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

  // El contexto se fija antes de que corra nada: guards, pipes y SPs quedan
  // dentro de la misma cadena asíncrona y `registrar_auditoria` puede firmar
  // con la IP real de quien hizo el cambio.
  fastify.addHook("onRequest", (req: any, _reply: unknown, done: () => void) => {
    iniciarContexto({
      ip: req.ip ?? "",
      userAgent: String(req.headers?.["user-agent"] ?? ""),
      requestId: String(req.headers?.["x-request-id"] ?? ""),
    });
    done();
  });

  await app.register(fastifyHelmet as any, {
    // Este proceso solo devuelve JSON: nada que ejecutar, nada que enmarcar.
    // La CSP de la SPA es otra y la pone nginx, que es quien sirve el HTML.
    contentSecurityPolicy: {
      useDefaults: false,
      directives: {
        "default-src": ["'none'"],
        "frame-ancestors": ["'none'"],
        "base-uri": ["'none'"],
        "form-action": ["'none'"],
      },
    },
    crossOriginResourcePolicy: { policy: "cross-origin" },
    hsts: config.get<string>("COOKIE_SECURE") === "true"
      ? { maxAge: 31536000, includeSubDomains: true }
      : false,
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
    // El saneo va primero: valida sobre el dato ya limpio, no sobre lo que se
    // pegó desde un Excel.
    new SanearEntradaPipe(),
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

