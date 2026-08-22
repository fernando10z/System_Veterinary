import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from "@nestjs/common";
import { FastifyReply } from "fastify";

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
    } else if (exception instanceof Error) {
      this.logger.error(exception.message, exception.stack);
      message = exception.message;
    } else {
      this.logger.error("Unknown exception", exception as any);
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
      case 422: return "VALIDATION_ERROR";
      case 429: return "TOO_MANY_REQUESTS";
      default: return "INTERNAL_ERROR";
    }
  }
}
