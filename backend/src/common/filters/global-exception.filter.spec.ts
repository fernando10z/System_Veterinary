import { describe, it, expect, vi } from "vitest";
import { BadRequestException, HttpException, HttpStatus, Logger } from "@nestjs/common";
import { GlobalExceptionFilter } from "./global-exception.filter";

function ejecutar(exception: unknown) {
  const reply = { status: vi.fn(), send: vi.fn() };
  reply.status.mockReturnValue(reply);
  const host = { switchToHttp: () => ({ getResponse: () => reply }) } as any;
  new GlobalExceptionFilter().catch(exception, host);
  return { status: reply.status.mock.calls[0][0], body: reply.send.mock.calls[0][0] };
}

describe("GlobalExceptionFilter", () => {
  vi.spyOn(Logger.prototype, "error").mockImplementation(() => undefined);
  vi.spyOn(Logger.prototype, "warn").mockImplementation(() => undefined);

  it("respeta el código y el mensaje de una HttpException", () => {
    const r = ejecutar(new BadRequestException({ code: "VALIDATION_ERROR", message: "Falta el nombre" }));
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ ok: false, error: { code: "VALIDATION_ERROR", message: "Falta el nombre" } });
  });

  it("no filtra el mensaje de un error que no es HTTP", () => {
    const r = ejecutar(new Error('relation "core.users" does not exist at 10.0.0.5:5432'));
    expect(r.status).toBe(500);
    expect(r.body.error.code).toBe("INTERNAL_ERROR");
    expect(r.body.error.message).toBe("Error interno del servidor");
    expect(JSON.stringify(r.body)).not.toContain("core.users");
  });

  it("traduce los 4xx de Fastify sin su texto interno", () => {
    const err = Object.assign(new Error("Request body is too large at /srv/app"), {
      statusCode: 413, code: "FST_ERR_CTP_BODY_TOO_LARGE",
    });
    const r = ejecutar(err);
    expect(r.status).toBe(413);
    expect(r.body.error.code).toBe("PAYLOAD_TOO_LARGE");
    expect(r.body.error.message).not.toContain("/srv/app");
  });

  it("un statusCode 5xx ajeno se trata como error interno genérico", () => {
    const r = ejecutar(Object.assign(new Error("ECONNREFUSED 127.0.0.1:6379"), { statusCode: 502 }));
    expect(r.status).toBe(500);
    expect(r.body.error.message).toBe("Error interno del servidor");
  });

  it("mapea 503 a SERVICE_UNAVAILABLE", () => {
    const r = ejecutar(new HttpException("sin servicio", HttpStatus.SERVICE_UNAVAILABLE));
    expect(r.status).toBe(503);
    expect(r.body.error.code).toBe("SERVICE_UNAVAILABLE");
  });
});
