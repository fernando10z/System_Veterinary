// =============================================================================
// PM2 — proceso del backend en producción.
//
//   pm2 start infra/pm2/ecosystem.config.js
//   pm2 save && pm2 startup
//
// El frontend NO va aquí: se compila a estáticos y los sirve nginx.
//
// Rotación de logs: PM2 no rota por sí solo y /var/log/veterp crece sin
// límite. Instalar el módulo una vez por servidor:
//   pm2 install pm2-logrotate
//   pm2 set pm2-logrotate:max_size 20M
//   pm2 set pm2-logrotate:retain 14
//   pm2 set pm2-logrotate:compress true
// (o una regla de logrotate del sistema con `copytruncate` sobre /var/log/veterp/*.log)
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
