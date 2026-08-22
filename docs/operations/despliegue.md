# Despliegue

## Antes de exponer el sistema

1. **Rol de aplicación.** El backend debe conectarse con `vet_app_user`, no con
   `postgres`. Ese rol solo tiene `EXECUTE` sobre `app.*`; sin acceso directo a las
   tablas, un SQL injection en un parámetro no alcanza a `core`.

   ```sql
   ALTER ROLE vet_app_user WITH PASSWORD '<contraseña larga y aleatoria>';
   ```

   ```
   DATABASE_URL=postgresql://vet_app_user:<clave>@host:5432/veterp
   ```

2. **Secretos.** Generar cada uno por separado, nunca reutilizar entre entornos:

   ```bash
   node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
   ```

   `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` (distinto), `COOKIE_SECRET`,
   `STORAGE_SECRET_KEY`.

3. **CORS.** `CORS_ORIGINS` debe listar solo el dominio real del frontend.

4. **Contraseñas de demostración.** Los usuarios semilla usan `Demo2026!`. Cambiarlas
   o eliminar los que no correspondan antes de entregar.

## Opción A — Docker

```bash
cat > infra/docker/.env <<'ENV'
POSTGRES_PASSWORD=...
JWT_ACCESS_SECRET=...
JWT_REFRESH_SECRET=...
COOKIE_SECRET=...
STORAGE_ACCESS_KEY=...
STORAGE_SECRET_KEY=...
PUBLIC_APP_URL=https://vet.tudominio.com
PUBLIC_API_URL=/api
ENV

docker compose -f infra/docker/docker-compose.prod.yml up -d --build
DB_HOST=localhost DB_PORT=5432 DB_NAME=veterp DB_USER=postgres \
  DB_PASSWORD=<la misma> bash db/scripts/apply-migrations.sh
```

Postgres, Redis y MinIO no publican puertos al host: solo son accesibles desde la red
del compose.

## Opción B — PM2 + nginx

```bash
# Backend
cd backend && npm ci && npm run build
pm2 start infra/pm2/ecosystem.config.js && pm2 save

# Frontend
cd frontend && npm ci
VITE_API_BASE_URL=/api npm run build
sudo cp -r dist/* /var/www/veterp/

# nginx
sudo cp infra/nginx/veterp.conf /etc/nginx/sites-available/veterp
sudo ln -s /etc/nginx/sites-available/veterp /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d vet.tudominio.com
```

## Actualizaciones

Las migraciones son idempotentes (`CREATE OR REPLACE`, `IF NOT EXISTS`), así que
reaplicarlas es seguro. Aun así, backup primero:

```bash
bash db/scripts/backup.sh
git pull
bash db/scripts/apply-migrations.sh
cd backend && npm ci && npm run build && pm2 reload veterp-api
cd frontend && npm ci && npm run build && sudo cp -r dist/* /var/www/veterp/
```

## Backups

`pg_dump -Fc` con timestamp. En producción conviene un cron diario y copia fuera del
servidor:

```
0 2 * * * cd /var/www/veterp && DB_NAME=veterp bash db/scripts/backup.sh
```

Los archivos clínicos (radiografías, consentimientos) viven en MinIO: el backup de
Postgres **no** los incluye. Hay que respaldar también el volumen de MinIO.

## Verificación

```bash
curl -s https://vet.tudominio.com/api/health
# {"ok":true,"data":{"db":true,"redis":true,"minio":true,"uptime":…}}
```
