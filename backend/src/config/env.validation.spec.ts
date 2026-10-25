import { describe, it, expect } from "vitest";
import { reglasProduccion } from "./env.validation";

describe("reglasProduccion", () => {
  const base = { NODE_ENV: "production", ENCRYPTION_KEY: "x".repeat(32) };

  it("en producción no acepta conectarse como postgres", () => {
    const e = reglasProduccion({ ...base, DATABASE_URL: "postgresql://postgres:x@db:5432/veterp" });
    expect(e.join()).toMatch(/vet_app_user/);
  });

  it("acepta vet_app_user, o postgres declarado a propósito", () => {
    expect(reglasProduccion({ ...base, DATABASE_URL: "postgresql://vet_app_user:x@db:5432/veterp" })).toEqual([]);
    expect(reglasProduccion({
      ...base, DATABASE_URL: "postgresql://postgres:x@db:5432/veterp", ALLOW_DB_SUPERUSER: "true",
    })).toEqual([]);
  });

  it("exige ENCRYPTION_KEY en producción y nada de esto en desarrollo", () => {
    expect(reglasProduccion({ NODE_ENV: "production", DATABASE_URL: "postgresql://vet_app_user:x@db/v" }).join())
      .toMatch(/ENCRYPTION_KEY/);
    expect(reglasProduccion({ NODE_ENV: "development", DATABASE_URL: "postgresql://postgres:x@db/v" })).toEqual([]);
  });
});
