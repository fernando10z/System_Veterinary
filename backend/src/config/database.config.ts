import { registerAs } from "@nestjs/config";

export default registerAs("database", () => ({
  url: process.env.DATABASE_URL,
  poolMin: Number(process.env.DATABASE_POOL_MIN ?? 2),
  poolMax: Number(process.env.DATABASE_POOL_MAX ?? 10),
  ssl: process.env.DATABASE_SSL === "true",
}));
