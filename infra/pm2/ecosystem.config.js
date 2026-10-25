// =============================================================================
// PM2 ecosystem — Producción ERP Veterinary (servidor erp-prod).
//
//   veterinary-api → backend NestJS (dist/main.js) en :3200
//
// El frontend NO corre en pm2: lo sirve Caddy (infra/caddy/veterinary.caddy)
// en 127.0.0.1:5373 junto con /api → :3200 y /veterinary → MinIO, con las
// mismas cabeceras de seguridad que frontend/nginx.conf. Un solo hostname en
// el Cloudflare Tunnel: veterinary.solvifylab.com → localhost:5373.
//
// Corre desde $APP/current (symlink al release activo), nunca desde src/.
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
  ],
};
