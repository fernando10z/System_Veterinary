import { registerAs } from "@nestjs/config";

export default registerAs("app", () => ({
  env: process.env.NODE_ENV ?? "development",
  port: Number(process.env.PORT ?? 3000),
  apiBaseUrl: process.env.API_BASE_URL ?? "http://localhost:3100",
  appName: process.env.APP_NAME ?? "ERP Veterinario",
  corsOrigins: (process.env.CORS_ORIGINS ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean),
  cookieSecret: process.env.COOKIE_SECRET ?? "dev-cookie-secret-change-me",
  logLevel: process.env.LOG_LEVEL ?? "info",
  logPretty: process.env.LOG_PRETTY === "true",
}));
