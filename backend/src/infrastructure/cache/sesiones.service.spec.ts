import { describe, it, expect, beforeEach } from "vitest";
import { SesionesService, duracionEnSegundos } from "./sesiones.service";

/** Redis en memoria con lo justo que usa SesionesService (sin TTL real). */
class RedisFalso {
  kv = new Map<string, string>();
  sets = new Map<string, Set<string>>();
  ttl = new Map<string, number>();
  async getdel(k: string) { const v = this.kv.get(k) ?? null; this.kv.delete(k); return v; }
  async srem(k: string, m: string) { return this.sets.get(k)?.delete(m) ? 1 : 0; }
  async smembers(k: string) { return [...(this.sets.get(k) ?? [])]; }
  async del(...ks: string[]) { let n = 0; for (const k of ks) { if (this.kv.delete(k) || this.sets.delete(k)) n++; } return n; }
  multi() {
    const ops: Array<() => void> = [];
    const m = {
      set: (k: string, v: string, _ex: string, t: number) => { ops.push(() => { this.kv.set(k, v); this.ttl.set(k, t); }); return m; },
      sadd: (k: string, v: string) => { ops.push(() => { if (!this.sets.has(k)) this.sets.set(k, new Set()); this.sets.get(k)!.add(v); }); return m; },
      expire: (k: string, t: number) => { ops.push(() => this.ttl.set(k, t)); return m; },
      exec: async () => { ops.forEach((o) => o()); return ops.map(() => [null, "OK"]); },
    };
    return m;
  }
}

describe("SesionesService", () => {
  let redis: RedisFalso;
  let sesiones: SesionesService;

  beforeEach(() => {
    redis = new RedisFalso();
    sesiones = new SesionesService({ raw: redis } as any);
  });

  it("registra la sesión con el TTL indicado y la indexa por usuario", async () => {
    await sesiones.registrar("j1", "u1", 3600);
    expect(redis.kv.get("refresh:j1")).toBe("u1");
    expect(redis.ttl.get("refresh:j1")).toBe(3600);
    expect(await redis.smembers("refresh:user:u1")).toEqual(["j1"]);
  });

  it("un refresh solo se consume una vez (rotación)", async () => {
    await sesiones.registrar("j1", "u1", 60);
    expect(await sesiones.consumir("j1")).toBe("u1");
    expect(await sesiones.consumir("j1")).toBeNull();
    expect(await redis.smembers("refresh:user:u1")).toEqual([]);
  });

  it("dos consumos simultáneos del mismo refresh: solo uno gana", async () => {
    await sesiones.registrar("j1", "u1", 60);
    const [a, b] = await Promise.all([sesiones.consumir("j1"), sesiones.consumir("j1")]);
    expect([a, b].filter(Boolean)).toEqual(["u1"]);
  });

  it("revocarTodas cierra todas las sesiones del usuario y ninguna de otro", async () => {
    await sesiones.registrar("j1", "u1", 60);
    await sesiones.registrar("j2", "u1", 60);
    await sesiones.registrar("j3", "u2", 60);
    expect(await sesiones.revocarTodas("u1")).toBe(2);
    expect(await sesiones.consumir("j1")).toBeNull();
    expect(await sesiones.consumir("j2")).toBeNull();
    expect(await sesiones.consumir("j3")).toBe("u2");
  });
});

describe("duracionEnSegundos", () => {
  it("entiende la sintaxis de JWT_REFRESH_EXPIRES", () => {
    expect(duracionEnSegundos("7d")).toBe(604800);
    expect(duracionEnSegundos("12h")).toBe(43200);
    expect(duracionEnSegundos("30m")).toBe(1800);
    expect(duracionEnSegundos("90")).toBe(90);
    expect(duracionEnSegundos(120)).toBe(120);
    expect(duracionEnSegundos("2w")).toBe(1209600);
  });
  it("usa el valor por defecto ante algo ilegible", () => {
    expect(duracionEnSegundos(undefined)).toBe(604800);
    expect(duracionEnSegundos("pronto", 10)).toBe(10);
  });
});
