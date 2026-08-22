import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from "@nestjs/common";
import { randomUUID } from "crypto";
import { Observable } from "rxjs";
import { tap } from "rxjs/operators";
import { FastifyReply } from "fastify";
import { AuthenticatedRequest } from "../types/authenticated-request.type";

@Injectable()
export class RequestIdInterceptor implements NestInterceptor {
  intercept(ctx: ExecutionContext, next: CallHandler): Observable<unknown> {
    const http = ctx.switchToHttp();
    const req = http.getRequest<AuthenticatedRequest>();
    const reply = http.getResponse<FastifyReply>();

    const incoming = (req.headers["x-request-id"] as string | undefined)?.trim();
    const id = incoming || randomUUID();
    req.id = id;
    reply.header("x-request-id", id);

    return next.handle().pipe(tap(() => undefined));
  }
}
