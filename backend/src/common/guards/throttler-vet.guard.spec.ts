import { describe, it, expect, vi, afterEach } from "vitest";
import { Logger, ServiceUnavailableException } from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import { ThrottlerException, ThrottlerGuard } from "@nestjs/throttler";
import { ThrottlerVetGuard } from "./throttler-vet.guard";
import { FALLA_CERRADO_KEY } from "../decorators/limite-credenciales.decorator";

function guardYContexto(fallaCerrado: boolean) {
  const handler = () => undefined;
  Reflect.defineMetadata(FALLA_CERRADO_KEY, fallaCerrado, handler);
  const guard = new ThrottlerVetGuard({ throttlers: [] } as any, {} as any, new Reflector());
  const ctx = { getHandler: () => handler, getClass: () => class {} } as any;
  return { guard, ctx };
}

describe("ThrottlerVetGuard", () => {
  vi.spyOn(Logger.prototype, "warn").mockImplementation(() => undefined);
  afterEach(() => vi.restoreAllMocks());

  it("sin Redis, una ruta de credenciales falla cerrada (503)", async () => {
    vi.spyOn(ThrottlerGuard.prototype, "canActivate").mockRejectedValue(new Error("ECONNREFUSED"));
    const { guard, ctx } = guardYContexto(true);
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it("sin Redis, el resto de rutas se deja pasar", async () => {
    vi.spyOn(ThrottlerGuard.prototype, "canActivate").mockRejectedValue(new Error("ECONNREFUSED"));
    const { guard, ctx } = guardYContexto(false);
    await expect(guard.canActivate(ctx)).resolves.toBe(true);
  });

  it("el 429 del límite se propaga tal cual", async () => {
    vi.spyOn(ThrottlerGuard.prototype, "canActivate").mockRejectedValue(new ThrottlerException());
    const { guard, ctx } = guardYContexto(false);
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(ThrottlerException);
  });
});
