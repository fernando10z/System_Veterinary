// =============================================================================
// PM2 — proceso del backend en producción.
//
//   pm2 start infra/pm2/ecosystem.config.js
//   pm2 save && pm2 startup
//
// El frontend NO va aquí: se compila a estáticos y los sirve nginx.
// =============================================================================

module.exports = {
  apps: [
    {
      name: "veterp-api",
      cwd: "/var/www/veterp/backend",
      script: "dist/main.js",
      // cluster aprovecha todos los núcleos; el backend no guarda estado en
      // memoria (las sesiones viven en Redis), así que escalar es seguro.
      exec_mode: "cluster",
      instances: "max",
      env: {
        NODE_ENV: "production",
        TZ: "America/Lima",
      },
      max_memory_restart: "512M",
      error_file: "/var/log/veterp/api-error.log",
      out_file: "/var/log/veterp/api-out.log",
      merge_logs: true,
      time: true,
    },
  ],
};
