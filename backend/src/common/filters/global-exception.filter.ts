import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from "@nestjs/common";
import { FastifyReply } from "fastify";

/**
 * Mensajes para los errores 4xx que no son HttpException: los lanza Fastify o
 * un plugin (cuerpo demasiado grande, multipart mal formado…) con un
 * `statusCode` propio. Su texto original está en inglés y a veces describe el
 * interior del servidor; al cliente le llega uno de estos.
 */
const MENSAJE_POR_STATUS: Record<number, string> = {
  400: "La petición no es válida",
  404: "Recurso no encontrado",
  406: "Formato no aceptado",
  413: "El archivo o la petición supera el tamaño permitido",
  415: "Tipo de contenido no admitido",
  429: "Demasiadas peticiones, intenta en un momento",
};

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const reply = ctx.getResponse<FastifyReply>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let code = "INTERNAL_ERROR";
    let message = "Error interno del servidor";
    let detail: unknown = undefined;

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const resp = exception.getResponse();
      if (typeof resp === "string") {
        message = resp;
      } else if (typeof resp === "object" && resp !== null) {
        const r = resp as Record<string, unknown>;
        message = (r.message as string) ?? message;
        code = (r.code as string) ?? this.statusToCode(status);
        detail = r.detail ?? r.errors;
      }
      code = code === "INTERNAL_ERROR" ? this.statusToCode(status) : code;
      if (status >= 500) {
        this.logger.error(`${code}: ${message}`, (exception as Error).stack);
      }
    } else {
      // Cualquier otra cosa es un fallo no previsto: un error de pg, de
      // ioredis, de MinIO, un TypeError… Su mensaje nombra tablas, hosts,
      // rutas del servidor o el dato que falló. Va al log con su traza; al
      // cliente, un texto genérico.
      const err = exception as { statusCode?: unknown; message?: unknown; stack?: string; code?: unknown };
      const sc = typeof err?.statusCode === "number" ? err.statusCode : undefined;
      if (sc !== undefined && sc >= 400 && sc < 500) {
        status = sc;
        code = this.statusToCode(sc);
        message = MENSAJE_POR_STATUS[sc] ?? MENSAJE_POR_STATUS[400];
        this.logger.warn(`${sc} ${String(err?.code ?? "")}: ${String(err?.message ?? "")}`);
      } else if (exception instanceof Error) {
        this.logger.error(exception.message, exception.stack);
      } else {
        this.logger.error(`Excepción desconocida: ${safeString(exception)}`);
      }
    }

    reply.status(status).send({
      ok: false,
      error: { code, message, ...(detail !== undefined ? { detail } : {}) },
    });
  }

  private statusToCode(status: number): string {
    switch (status) {
      case 400: return "BAD_REQUEST";
      case 401: return "UNAUTHORIZED";
      case 403: return "FORBIDDEN";
      case 404: return "NOT_FOUND";
      case 409: return "CONFLICT";
      case 413: return "PAYLOAD_TOO_LARGE";
      case 415: return "UNSUPPORTED_MEDIA_TYPE";
      case 422: return "VALIDATION_ERROR";
      case 429: return "TOO_MANY_REQUESTS";
      case 503: return "SERVICE_UNAVAILABLE";
      default: return status >= 500 ? "INTERNAL_ERROR" : "BAD_REQUEST";
    }
  }
}

function safeString(v: unknown): string {
  try {
    return typeof v === "string" ? v : JSON.stringify(v);
  } catch {
    return String(v);
  }
}
