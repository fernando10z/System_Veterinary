// =============================================================================
// PM2 ecosystem — Producción ERP Veterinary.
//
//   veterinary-api → backend NestJS (dist/main.js) en :3200
//   veterinary-web → frontend Vue (estático SPA) en :5373
//
// Un solo hostname en el Cloudflare Tunnel: /api/* → :3200, el resto → :5373.
// Así la cookie de sesión viaja al mismo origen. Las descargas (URLs firmadas
// de MinIO) salen por files.solvifylab.com (STORAGE_PUBLIC_ENDPOINT).
//
// Ambos corren desde $APP/current (symlink al release activo), nunca desde src/.
// Publicar: infra/scripts/deploy.sh   ·   Volver atrás: deploy.sh rollback
//
// Arranque inicial:
//   pm2 start infra/pm2/ecosystem.config.js && pm2 save
// =============================================================================
const APP = "/srv/apps/erp-veterinary";
const LOGS = "/var/log/apps/erp-veterinary";

module.exports = {
  apps: [
    {
      name: "veterinary-api",
      namespace: "veterinary",
      // ConfigModule lee .env del cwd: current/backend/.env → shared/backend.env
      cwd: `${APP}/current/backend`,
      script: "dist/main.js",
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      max_memory_restart: "400M",
      kill_timeout: 10000,
      env: { NODE_ENV: "production", TZ: "America/Lima" },
      out_file: `${LOGS}/api-out.log`,
      error_file: `${LOGS}/api-err.log`,
      merge_logs: true,
      time: true,
    },
    {
      // Sirve el build estático como SPA. Lee cada archivo por request a través
      // del symlink, así que un deploy de frontend no necesita reiniciarlo.
      name: "veterinary-web",
      namespace: "veterinary",
      script: "serve",
      env: {
        PM2_SERVE_PATH: `${APP}/current/frontend`,
        PM2_SERVE_PORT: "5373",
        PM2_SERVE_SPA: "true",
        PM2_SERVE_HOMEPAGE: "/index.html",
      },
      autorestart: true,
      out_file: `${LOGS}/web-out.log`,
      error_file: `${LOGS}/web-err.log`,
      merge_logs: true,
      time: true,
    },
  ],
};
