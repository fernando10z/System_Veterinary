import { describe, it, expect, vi, beforeEach } from "vitest";
import { UnauthorizedException } from "@nestjs/common";
import { AuthService } from "./auth.service";

const perfil = {
  user: { id: "u1", email: "a@b.pe", empresa_id: "e1", is_super_admin: false, must_change_password: false },
  rol: { codigo: "veterinario" },
  permisos: [],
  empresa: null,
} as any;

describe("AuthService.refresh", () => {
  let sesiones: any;
  let repo: any;
  let jwt: any;
  let auth: AuthService;
  const config = { get: (k: string) => ({ JWT_REFRESH_EXPIRES: "12h" } as Record<string, string>)[k] } as any;

  beforeEach(() => {
    sesiones = {
      consumir: vi.fn(),
      registrar: vi.fn().mockResolvedValue(undefined),
      revocarTodas: vi.fn().mockResolvedValue(1),
      revocar: vi.fn(),
    };
    repo = { perfil: vi.fn().mockResolvedValue(perfil), cambiarPassword: vi.fn().mockResolvedValue({ updated: true }), resetPassword: vi.fn() };
    jwt = {
      verifyAsync: vi.fn().mockResolvedValue({ sub: "u1", jti: "j-viejo" }),
      signAsync: vi.fn().mockResolvedValue("token"),
    };
    auth = new AuthService(repo, jwt, config, sesiones);
  });

  it("rota: consume el jti viejo y registra uno nuevo con el TTL configurado", async () => {
    sesiones.consumir.mockResolvedValue("u1");
    const r = await auth.refresh("rt");
    expect(sesiones.consumir).toHaveBeenCalledWith("j-viejo");
    expect(sesiones.registrar).toHaveBeenCalledTimes(1);
    const [jti, userId, ttl] = sesiones.registrar.mock.calls[0];
    expect(jti).not.toBe("j-viejo");
    expect(userId).toBe("u1");
    expect(ttl).toBe(12 * 3600);
    expect(r.access_token).toBe("token");
  });

  it("rechaza un refresh ya usado o revocado", async () => {
    sesiones.consumir.mockResolvedValue(null);
    await expect(auth.refresh("rt")).rejects.toBeInstanceOf(UnauthorizedException);
    expect(repo.perfil).not.toHaveBeenCalled();
    expect(sesiones.registrar).not.toHaveBeenCalled();
  });

  it("rechaza si el jti pertenece a otro usuario", async () => {
    sesiones.consumir.mockResolvedValue("otro");
    await expect(auth.refresh("rt")).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it("no emite sesión si la cuenta ya no está activa (el SP rechaza)", async () => {
    sesiones.consumir.mockResolvedValue("u1");
    repo.perfil.mockRejectedValue(new UnauthorizedException("La cuenta no está activa"));
    await expect(auth.refresh("rt")).rejects.toBeInstanceOf(UnauthorizedException);
    expect(sesiones.registrar).not.toHaveBeenCalled();
  });

  it("un token con firma inválida no toca Redis", async () => {
    jwt.verifyAsync.mockRejectedValue(new Error("invalid signature"));
    await expect(auth.refresh("rt")).rejects.toBeInstanceOf(UnauthorizedException);
    expect(sesiones.consumir).not.toHaveBeenCalled();
  });

  it("cambiar la contraseña cierra todas las sesiones y entrega un par nuevo", async () => {
    const r = await auth.cambiarPassword({ sub: "u1", empresa_id: "e1", is_super_admin: false } as any, "a", "b");
    expect(sesiones.revocarTodas).toHaveBeenCalledWith("u1");
    expect(sesiones.revocarTodas.mock.invocationCallOrder[0])
      .toBeLessThan(sesiones.registrar.mock.invocationCallOrder[0]);
    expect(r).toMatchObject({ updated: true, access_token: "token", refresh_token: "token" });
  });

  it("el reset por correo cierra las sesiones y no devuelve el user_id", async () => {
    repo.resetPassword.mockResolvedValue({ updated: true, user_id: "u1" });
    const r = await auth.resetPassword("tok", "Nueva2026!");
    expect(sesiones.revocarTodas).toHaveBeenCalledWith("u1");
    expect(r).toEqual({ updated: true });
  });
});
