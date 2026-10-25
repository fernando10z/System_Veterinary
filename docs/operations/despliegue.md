# Despliegue

## Antes de exponer el sistema

1. **Rol de aplicación.** El backend se conecta con `erp_veterinary_user`, no con
   `postgres`. Ese rol solo tiene `EXECUTE` sobre `app.*` (y `PUBLIC` no tiene
   `EXECUTE` sobre nada de `app`); sin acceso directo a las tablas, un SQL
   injection en un parámetro no alcanza a `core`. Con `NODE_ENV=production` el
   backend **se niega a arrancar** si `DATABASE_URL` usa `postgres` (salvo
   `ALLOW_DB_SUPERUSER=true`, a propósito).

   La contraseña del rol la fija `apply-migrations.sh` cuando recibe
   `VET_APP_PASSWORD` (el compose de producción lo hace en cada arranque):

   ```bash
   VET_APP_PASSWORD="$(openssl rand -hex 32)" DB_HOST=… DB_NAME=veterp \
     bash db/scripts/apply-migrations.sh
   ```

   ```
   DATABASE_URL=postgresql://erp_veterinary_user:<clave>@host:5432/veterp
   ```

   La clave va dentro de una URL: usar hex o base64url.

2. **Secretos.** Generar cada uno por separado, nunca reutilizar entre entornos:

   ```bash
   openssl rand -hex 32
   ```

   `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` (distinto), `COOKIE_SECRET`,
   `ENCRYPTION_KEY` (obligatoria en producción: cifra las credenciales del PSE;
   si cambia, hay que volver a cargarlas), `VET_APP_PASSWORD`, `REDIS_PASSWORD`,
   `MINIO_ROOT_PASSWORD`, `STORAGE_SECRET_KEY`.

3. **CORS.** `CORS_ORIGINS` debe listar solo el dominio real del frontend.

4. **Sin datos de demostración.** Las migraciones ya no crean empresas ni
   usuarios: `98_seeds_base.sql` solo carga permisos, roles y taxonomía. Las
   dos clínicas de demo y sus usuarios (`Demo2026!`) viven en `db/seeds/` y
   solo se aplican con `SEED_DEMO=1` (desarrollo, CI y el snapshot). El script
   se niega a cargarlos en una base cuyo nombre no diga demo/dev/test/ci.

5. **Primer super admin.** Se crea una vez, con una clave que solo conoce quien
   lo ejecuta. La cuenta nace con `must_change_password`: sirve para entrar una
   vez y cambiarla. Si el correo ya existe, el script se detiene sin tocarlo.

   ```bash
   # Opción A (Docker)
   docker compose -f infra/docker/docker-compose.prod.yml run --rm migrate \
     bash /db/scripts/crear-superadmin.sh
   # Opción B
   DB_HOST=127.0.0.1 DB_PORT=5432 DB_NAME=veterp DB_PASSWORD=… \
     bash db/scripts/crear-superadmin.sh
   ```

   Pide correo, nombre, DNI y contraseña (sin eco). Para automatizarlo:
   `SUPERADMIN_EMAIL`, `SUPERADMIN_PASSWORD`, `SUPERADMIN_NOMBRES`,
   `SUPERADMIN_APELLIDO`, `SUPERADMIN_DNI`.

## Opción A — Docker

```bash
cp infra/docker/prod.env.example infra/docker/.env
chmod 600 infra/docker/.env
# completar todos los secretos (openssl rand -hex 32)

docker compose -f infra/docker/docker-compose.prod.yml up -d --build
docker compose -f infra/docker/docker-compose.prod.yml run --rm migrate \
  bash /db/scripts/crear-superadmin.sh
```

Qué hace el compose:

| Servicio | Papel |
|---|---|
| `postgres` | Base. Sin puerto publicado. |
| `migrate` | Aplica `db/migrations/` (idempotentes) y fija la clave de `erp_veterinary_user`. Corre y termina en cada `up`; el backend espera a que termine bien. No carga demo. |
| `redis` | Con `requirepass` y `maxmemory-policy noeviction`: guarda las sesiones y el contador de intentos de login, que no se pueden perder por falta de memoria. |
| `minio` | Archivos clínicos. Versión fija (fork comunitario `pgsty/minio`: MinIO ya no publica imágenes en Docker Hub). |
| `minio-init` | Crea el bucket y un usuario `STORAGE_ACCESS_KEY` con una política limitada a ese bucket. El backend no usa la credencial root. |
| `api` | Backend. Sin puerto publicado; healthcheck contra `/api/health` (503 si falta la base, Redis o MinIO). |
| `web` | nginx: sirve la SPA y reenvía `/api` al backend y `/vet-docs` a MinIO. Es el único puerto publicado (`WEB_PORT`). |

Todos los servicios llevan `restart: unless-stopped`, límite de memoria y logs
rotados (`json-file`, 5 × 10 MB).

**TLS.** `web` habla HTTP. Delante va un nginx del host que termina TLS (el
server de 443 de `infra/nginx/veterp.conf`, con `proxy_pass
http://127.0.0.1:8080` en lugar de servir archivos) o Caddy. En ese caso:

```
WEB_PORT=127.0.0.1:8080   # que solo lo alcance el proxy del host
TRUST_PROXY=2             # proxy del host + nginx de web
```

El proxy del host debe mandar `X-Forwarded-Proto: https`: `web` solo emite HSTS
cuando lo recibe.

## Opción B — PM2 + nginx

```bash
# Base (Postgres del host): esquema + clave del rol, SIN demo
VET_APP_PASSWORD=… DB_HOST=127.0.0.1 DB_PORT=5432 DB_NAME=veterp DB_PASSWORD=… \
  bash db/scripts/apply-migrations.sh
DB_HOST=127.0.0.1 DB_PORT=5432 DB_NAME=veterp DB_PASSWORD=… \
  bash db/scripts/crear-superadmin.sh

# Backend (backend/.env con NODE_ENV=production, DATABASE_URL de erp_veterinary_user,
# REDIS_PASSWORD, STORAGE_PUBLIC_ENDPOINT=https://vet.tudominio.com,
# COOKIE_SECURE=true, TRUST_PROXY=1, ENCRYPTION_KEY)
cd backend && npm ci && npm run build
pm2 start infra/pm2/ecosystem.config.js && pm2 save
pm2 install pm2-logrotate   # ver notas en ecosystem.config.js

# Frontend
cd frontend && npm ci
VITE_API_BASE_URL=/api npm run build
sudo cp -r dist/* /var/www/veterp/
```

### nginx y certificado (Let's Encrypt)

`infra/nginx/veterp.conf` trae el server de 80 (solo desafío ACME y redirección
a HTTPS) y el de 443 con TLS 1.2/1.3. Las cabeceras de seguridad (CSP,
X-Frame-Options, nosniff, Referrer-Policy, HSTS) viven en un snippet que se
incluye en el server **y** en cada `location` con `add_header` propio: en nginx
un `add_header` dentro de un `location` anula todos los heredados, y así era
como `index.html` y `/assets/` salían sin CSP.

```bash
sudo apt install nginx certbot
sudo mkdir -p /var/www/certbot /etc/nginx/snippets
sudo cp infra/nginx/snippets/veterp-security-headers.conf /etc/nginx/snippets/
sudo cp infra/nginx/veterp.conf /etc/nginx/sites-available/veterp
sudo sed -i 's/vet.tudominio.com/<tu dominio>/g' /etc/nginx/sites-available/veterp
sudo ln -s /etc/nginx/sites-available/veterp /etc/nginx/sites-enabled/

# Primera vez: aún no hay certificado. Comentar el server de 443, recargar,
# emitir y volver a descomentar.
sudo nginx -t && sudo systemctl reload nginx
sudo certbot certonly --webroot -w /var/www/certbot -d <tu dominio> \
  --email <correo> --agree-tos --no-eff-email
sudo nginx -t && sudo systemctl reload nginx

# Renovación: el paquete instala un timer (systemctl list-timers | grep certbot).
# Recargar nginx tras cada renovación:
echo -e '#!/bin/sh\nsystemctl reload nginx' | \
  sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
sudo certbot renew --dry-run
```

### Archivos clínicos por el mismo dominio

El backend habla con MinIO por la red interna, pero las URLs firmadas (descarga
y subida directa) las abre el navegador. Por eso se firman contra
`STORAGE_PUBLIC_ENDPOINT` (el propio dominio) y nginx reenvía `/vet-docs/` a
MinIO **conservando el Host**, que es parte de la firma. Así la CSP puede
quedarse en `'self'`. Si se sirvieran desde otro dominio, hay que añadirlo a
`img-src` y `connect-src`.

MinIO sin Docker: crear el usuario de la aplicación como hace `minio-init` en el
compose (política con `s3:GetObject`, `PutObject`, `DeleteObject`,
`ListBucket`, `ListBucketMultipartUploads`… solo sobre `vet-docs`) y usar esa
credencial en `STORAGE_ACCESS_KEY`/`STORAGE_SECRET_KEY`, no la root.

### Subidas de archivos

- `POST /api/archivos` (multipart): el archivo pasa en stream a MinIO sin
  cargarse en memoria; se comprueban sus primeros bytes contra la firma del tipo
  declarado (PDF, PNG, JPEG, WebP, TIFF, DICOM…). Un HTML con
  `type=image/png` se rechaza. Límite 50 MB, solo en esa ruta.
- `GET /api/archivos/ticket-subida?nombre=…[&tipo=…]`: devuelve `{url, campos}`
  para un **POST con política firmada** (ya no un PUT prefirmado): MinIO exige
  la clave exacta, el `Content-Type` exacto y entre 1 byte y 50 MB. Solo para
  PDF, imágenes y DICOM.
- El resto de la API acepta cuerpos de 1 MB como máximo.

## Actualizaciones

Las migraciones son idempotentes (`CREATE OR REPLACE`, `IF NOT EXISTS`), así que
reaplicarlas es seguro, y **nunca reescriben contraseñas** de usuarios
existentes. Aun así, backup primero:

```bash
bash db/scripts/backup.sh
git pull
# Opción A
docker compose -f infra/docker/docker-compose.prod.yml up -d --build
# Opción B
VET_APP_PASSWORD=… bash db/scripts/apply-migrations.sh
cd backend && npm ci && npm run build && pm2 reload veterp-api
cd frontend && npm ci && npm run build && sudo cp -r dist/* /var/www/veterp/
```

## Sesiones

- Refresh token con whitelist en Redis; la entrada vence con
  `JWT_REFRESH_EXPIRES`. La rotación es atómica (`GETDEL`): un refresh sirve
  una sola vez aunque lleguen dos peticiones a la vez.
- Cambiar o resetear la contraseña, desactivar, eliminar o cambiar el rol de un
  usuario **cierra todas sus sesiones**. `fn_auth_perfil` rechaza además a una
  cuenta no activa, así que la baja corta también la renovación.
- `POST /auth/cambiar-password` devuelve un par nuevo (`access_token`,
  `refresh_token`) para quien la cambió.
- Los tokens de reseteo por correo se guardan como SHA-256.
- Portal del propietario: bloqueo de 15 minutos tras 5 intentos fallidos, igual
  que el staff, y la misma respuesta genérica para documento inexistente y
  acceso deshabilitado.

## Proxy inverso y límite de peticiones

`TRUST_PROXY` declara cuántos proxies hay delante del backend. Detrás del nginx
de este despliegue es **1** (2 si además hay un proxy TLS delante de `web`); sin
proxy, se deja vacío.

No es cosmético: con `trustProxy: true` —que era lo que había— Fastify se creía
cualquier `X-Forwarded-For`, incluida la que escribiera el cliente. El límite de
10 intentos de login por minuto se saltaba rotando esa cabecera, y la IP que
quedaba en la bitácora era la que el atacante quisiera. Ponerlo a un número
mayor que el de proxies reales reabre exactamente el mismo agujero.

El contador del límite vive en Redis (`ThrottlerRedisStorage`), no en la memoria
del proceso: PM2 arranca en cluster y cada núcleo llevaba su propia cuenta. Si
Redis no responde, las rutas de credenciales (login, reset, portal) responden
**503** —sin contador no hay límite— y el resto sigue funcionando.

## Snapshot versionado de la base

`db/dumps/vet_demo.sql.gz` es el esquema completo, los catálogos y las dos
empresas de demostración. Sirve para levantar el ERP en una máquina nueva sin
esperar las migraciones:

```bash
DB_NAME=vet_local VET_APP_PASSWORD=… bash db/scripts/restaurar-snapshot.sh
```

**Las migraciones siguen siendo la fuente de verdad.** `exportar-snapshot.sh`
construye una base temporal con `db/migrations/` + `db/seeds/` (`SEED_DEMO=1`),
la vuelca y la borra. Hay que regenerarlo después de tocar una migración o una
semilla. El volcado va sin ACLs: la restauración vuelve a aplicar
`90_grants.sql`. **Nunca** restaurar el snapshot en producción: trae usuarios
con clave conocida.

## Backups

`db/scripts/backup.sh` respalda la base (`pg_dump -Fc`, validado con
`pg_restore --list`) y, con `MINIO_BACKUP=1`, los archivos clínicos (`mc
mirror` incremental del bucket). Retención local de 14 días
(`BACKUP_RETENTION_DAYS`), cifrado opcional con GPG, copia fuera del servidor
con `rclone` o `aws s3`, log en `BACKUP_DIR/backup.log` y código de salida
distinto de 0 ante cualquier fallo (con `BACKUP_ALERT_CMD` para avisar).

No tiene defaults de desarrollo en producción: exige `DB_NAME` y
`DB_CONTAINER` (Docker) o `DB_HOST`. La configuración va en
`/etc/veterp/backup.env` (plantilla: `infra/systemd/backup.env.example`).

```bash
sudo mkdir -p /etc/veterp && sudo cp infra/systemd/backup.env.example /etc/veterp/backup.env
sudo chmod 600 /etc/veterp/backup.env     # completar
sudo bash db/scripts/backup.sh            # probar a mano
```

**Programarlo** (systemd; el repo en `/opt/veterp`):

```bash
sudo cp infra/systemd/veterp-*.service infra/systemd/veterp-*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now veterp-backup.timer veterp-restore-test.timer
systemctl list-timers | grep veterp
journalctl -u veterp-backup.service
```

- `veterp-backup.timer`: todos los días a las 02:30.
- `veterp-restore-test.timer`: los domingos, `restore-test.sh` restaura el
  último backup en una base temporal, comprueba que tenga los SPs, los permisos
  y los grants de `erp_veterinary_user`, y la borra. Un backup que nunca se restauró
  es una hipótesis.

Con cron en lugar de systemd:

```
30 2 * * *  root  VETERP_BACKUP_ENV=/etc/veterp/backup.env bash /opt/veterp/db/scripts/backup.sh
0 4 * * 0   root  VETERP_BACKUP_ENV=/etc/veterp/backup.env bash /opt/veterp/db/scripts/restore-test.sh
```

**Restaurar:**

```bash
DB_CONTAINER=veterp-prod-postgres-1 DB_NAME=veterp \
  bash db/scripts/restore.sh /var/backups/veterp/veterp_20260901_023000.dump
```

Pide escribir el nombre de la base para confirmar (o `FORCE=1`). Después de
restaurar vuelve a aplicar `90_grants.sql` —sin eso el backend no podría
llamar a ningún SP— y, con `VET_APP_PASSWORD`, fija la clave del rol. Los
archivos de MinIO se reponen con `mc mirror BACKUP_DIR/minio/vet-docs
<alias>/vet-docs`.

## Verificación

```bash
curl -s https://vet.tudominio.com/api/health
# 200 {"ok":true,"data":{"db":true,"redis":true,"minio":true,"uptime":…}}
# 503 si cualquiera de los tres no responde
```

El CI (`.github/workflows/ci.yml`) levanta el compose de desarrollo, aplica
migraciones con `SEED_DEMO=1`, compila y prueba el backend, lo arranca y corre
`scripts/verificar-api.sh` y `scripts/flujo-clinico.sh`.
