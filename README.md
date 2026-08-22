# ERP Veterinario

ERP multi-empresa para clínicas veterinarias. Réplica funcional de `System_Veterinary`
(PHP + MySQL) sobre la arquitectura de `System_ERP`: **toda la lógica de negocio vive
en stored procedures de PostgreSQL**; el backend es un orquestador HTTP que invoca SPs
y propaga la respuesta `{ok, data, error, meta}`.

Cada empresa es un **negocio independiente**: su cartera de clientes, sus pacientes,
su historia clínica, su inventario, su facturación y su caja no los ve ninguna otra.

**Stack**: NestJS 10 + Fastify + PostgreSQL 16 (SPs) + Redis + MinIO + Vue 3 + Vite + nginx.

---

## 1. Arranque rápido

```bash
# 1. Infraestructura (Postgres 5435, Redis 6382, MinIO 9102/9103)
docker compose -f infra/docker/docker-compose.dev.yml up -d

# 2. Schema + datos de demostración
bash db/scripts/apply-migrations.sh

# 3. Backend  → http://localhost:3100/api
cd backend && npm install && cp .env.example .env && npm run start:dev

# 4. Frontend → http://localhost:5174
cd frontend && npm install && npm run dev
```

`db/scripts/apply-migrations.sh` usa el `psql` del host y, si no está instalado, cae
automáticamente al del contenedor `veterp_postgres_dev`.

### Cuentas de demostración

Todas con contraseña **`Demo2026!`**:

| Correo | Rol | Alcance |
|---|---|---|
| `admin@vetpatitas.pe` | Super administrador | Todas las sedes |
| `gerencia@vetpatitas.pe` | Gerencia | Todas las sedes (solo lectura) |
| `administracion@vetpatitas.pe` | Administrador de empresa | Vet Patitas Miraflores |
| `jperez@vetpatitas.pe` | Veterinario | Miraflores |
| `mrojas@vetpatitas.pe` | Veterinario (cirugía) | Miraflores |
| `recepcion@vetpatitas.pe` | Recepción | Miraflores |
| `almacen@vetpatitas.pe` | Almacén | Miraflores |

Portal del propietario (`/portal/login`): documento `44556677` o `41223344`,
contraseña `Mascota2026!`.

---

## 2. Por qué está construido así

### Decisiones arquitectónicas

| Tema | Decisión | Por qué |
|---|---|---|
| Lógica de negocio | 100 % en SPs de PostgreSQL | Misma decisión que System_ERP. Las reglas clínicas y contables viven junto a los datos: no hay forma de saltárselas desde otro cliente. |
| Organización del código | Modular vertical (un módulo = una carpeta) | Para entender "facturación" abrís UNA carpeta. Escala a 20+ dominios. |
| Capas por módulo | `controller + service + repository + dto/` | Sin `domain/application/infrastructure`: no aportan cuando la lógica está en SPs. |
| Multi-tenancy | Columna `empresa_id` resuelta en SPs | El backend solo propaga `(user_id, empresa_id, is_super_admin)`. 46 de 60 tablas la llevan. |
| Cartera | Clientes y pacientes son **de cada empresa** | Son negocios independientes: el documento es único por empresa, no globalmente. Ver [ADR-002](docs/decisions/002-cartera-por-empresa.md). |
| Historia clínica | Línea de tiempo única (`core.historia_clinica`) | Un solo SELECT ordenado devuelve consultas, vacunas, cirugías y notas del paciente. |
| Movimiento de stock | Puerta única `internal.mover_stock` + trigger | Un solo camino toca el inventario: no hay descuadres entre el kardex y el saldo. |
| Auth backoffice | JWT access (15 m) + refresh (7 d, whitelist en Redis) | Permite revocar una sesión concreta sin esperar a que expire. |
| Auth portal | JWT con `type=portal`, issuer/audience propios | Un token del portal no valida contra el guard del staff, ni al revés. |
| Storage | MinIO con URLs prefirmadas | Radiografías y consentimientos no pasan por el backend al descargarse. |

### Modelo de acceso multi-empresa

El alcance de cada usuario lo define el **scope de su rol** (`core.roles.scope`),
validado por el trigger `trg_users_validate_rol_scope`:

| `scope_rol` | `is_super_admin` | `empresa_id` | Ve | Roles |
|---|---|---|---|---|
| `global` | `true` | **NULL** | Todas las empresas, sin restricción | `super_admin` |
| `global_restricted` | `false` | **NULL** | Todas las empresas, sin privilegios de super admin | `gerente` |
| `empresa` | `false` | **NOT NULL** | Solo su empresa | `admin_empresa`, `veterinario`, `recepcion`, `almacen`, `contador` |

**Regla al escribir SPs de lectura**: filtrar siempre con
`(internal.es_acceso_global(p_user_id, p_is_super_admin) OR x.empresa_id = v_emp)`,
nunca con `p_is_super_admin` a secas — eso ocultaría datos a gerencia.

**Regla al escribir SPs de escritura**: la empresa se toma del contexto
(`internal.empresa_efectiva`) o se hereda del registro padre, **nunca del payload**.
Por eso una mascota no puede quedar en una empresa distinta a la de su dueño, y el
portal no puede pedir cita en una empresa que no es la suya.

#### Lo único que comparten todas las empresas

Identidad del sistema (`empresas`, `roles`, `permisos`, `users`) y taxonomía de
referencia (`especies`, `razas`, `especializaciones`). La taxonomía **solo la edita
el super admin**, que es el operador del ERP: sin esa restricción, el administrador
de una empresa podría renombrar una especie que usan las demás.

### Convención de respuesta

Todo SP devuelve `{ok, data?, error?, meta?}`. `SpExecutorService` lo desempaqueta:
`ok:true` → retorna `data`; `ok:false` → lanza `HttpException` con el `error.code`
mapeado al status HTTP correcto (`NOT_FOUND`→404, `FORBIDDEN`→403, `CONFLICT`→409,
`BUSINESS_RULE`/`VALIDATION_ERROR`→422). El cliente del frontend
(`shared/api/client.js`) parsea el mismo shape.

---

## 3. Estructura

```
System_VeterinaryERP/
├── db/
│   ├── migrations/         28 archivos: tablas, triggers, helpers, 151 SPs, seeds
│   └── scripts/            apply-migrations, reset-dev, backup, restore
├── backend/                NestJS + Fastify — 19 módulos
│   └── src/
│       ├── config/         validación de entorno + 6 configs
│       ├── common/         guards (JWT staff + JWT portal), decoradores, filtros
│       ├── infrastructure/ pool pg + SpExecutor, Redis, MinIO, mail, logger, health
│       └── modules/        auth users roles empresas dashboard clientes mascotas
│                           citas clinico catalogos inventario compras facturacion
│                           pagos rrhh reportes portal auditoria archivos
├── frontend/               Vue 3 + Vite — 18 módulos espejo del backend
│   └── src/
│       ├── shared/         client.js, composables, 20 primitivos de UI
│       ├── layouts/        MainLayout, Sidebar, Topbar, PageHeader
│       ├── styles/         globals.css (sistema de diseño) + patterns.css
│       └── modules/        cada uno con api/ + pages/ + components/
├── infra/
│   ├── docker/             compose de dev y de producción
│   ├── nginx/              reverse proxy + SPA
│   └── pm2/                proceso del backend en cluster
└── docs/                   arquitectura, base de datos, API y operación
```

---

## 4. Qué cubre el sistema

| Módulo | Qué resuelve |
|---|---|
| **Agenda** | Tablero por estado (programada → confirmada → en sala → en atención → atendida), cálculo de huecos libres por veterinario cruzando horario de sede, turnos y permisos aprobados. Bloquea solapamientos. |
| **Pacientes** | Ficha clínica con alertas de alergias, curva de peso, carné de vacunación y línea de tiempo unificada. |
| **Propietarios** | Cartera privada de cada empresa, con deuda, mascotas vinculadas y bitácora de contactos. |
| **Historia clínica** | Consulta con estructura SOAP y constantes fisiológicas, cierre firmado e inmutable, cirugías con consentimiento obligatorio, hospitalización con evoluciones por turno, exámenes y documentos. |
| **Vacunación** | Protocolos por especie que calculan el refuerzo y generan recordatorios automáticos de contacto. |
| **Inventario** | Kardex completo, lotes con vencimiento, alertas de stock crítico y consumo clínico que descuenta stock en el acto. |
| **Compras** | Proveedores, órdenes con recepción total o parcial que crea lotes y mueve inventario, y pagos con saldo. |
| **Facturación** | Emite boleta/factura/nota de venta desde lo pendiente de cobrar del paciente. Valida que una factura exija RUC. Desagrega IGV. |
| **Cobranzas** | Aging por tramos de mora, cobros que se imputan a los comprobantes más antiguos si no se detalla. |
| **Caja** | Apertura por turno, movimientos y arqueo que compara efectivo contado contra esperado. |
| **Equipo** | Carga de trabajo, asistencia con detección de tardanza, permisos que bloquean la agenda al aprobarse, evaluaciones. |
| **Reportes** | Ventas, producción clínica, valorización de inventario y comparativo ejecutivo entre empresas. |
| **Portal** | El propietario ve sus mascotas, historial (sin notas internas), citas y comprobantes, y puede solicitar cita. |
| **Auditoría** | Bitácora con diff campo a campo de cada cambio. |

---

## 5. Reglas de negocio que el sistema hace cumplir

Están en los SPs, no en la UI, así que ningún cliente puede saltárselas:

- Una **consulta cerrada** es un documento firmado: no se reescribe. Para agregar algo, se registra una nota o una nueva consulta.
- No se cierra una consulta **sin diagnóstico**.
- Solo un **veterinario colegiado** puede firmar una consulta.
- Una **cirugía** no se cierra sin consentimiento informado firmado.
- Una **salida de inventario** nunca deja el stock en negativo.
- Una **factura** exige que el cliente tenga RUC; si no, corresponde boleta.
- Un **comprobante aceptado por SUNAT** no se anula: corresponde nota de crédito.
- Al **anular un comprobante**, sus servicios e insumos vuelven a quedar pendientes de cobro.
- Un **paciente con historia clínica** no se elimina: se marca inactivo y la historia se conserva.
- Marcar una mascota como **fallecida** suspende sus tratamientos, cancela sus citas futuras y apaga sus recordatorios.
- Nadie **aprueba su propio permiso** ni cambia el estado de su propia cuenta.
- Un rol de **alcance global** no puede estar anclado a una empresa (trigger).
- Un usuario **no puede alcanzar datos de otra empresa** aunque conozca el id. Todo SP
  que recibe un id comprueba la pertenencia con `internal.es_de_empresa` y responde
  `NOT_FOUND` si no corresponde — no `FORBIDDEN`, para no revelar que el registro
  existe en otra empresa. Verificado con 39 intentos de acceso cruzado (lectura,
  edición, anulación, movimientos de stock y de caja): todos bloqueados.

---

## 6. Operación

```bash
# Reconstruir la base de desarrollo desde cero
ALLOW_RESET=yes bash db/scripts/reset-dev.sh

# Backup / restauración
bash db/scripts/backup.sh
bash db/scripts/restore.sh db/backups/vet_demo_YYYYMMDD_HHMMSS.dump

# Producción con Docker
docker compose -f infra/docker/docker-compose.prod.yml up -d --build

# Producción con PM2 + nginx
pm2 start infra/pm2/ecosystem.config.js
```

Antes de exponer el sistema, ver `docs/operations/despliegue.md`: cambiar la contraseña
de `vet_app_user`, generar los secretos JWT y apuntar el backend a ese rol (que solo
tiene `EXECUTE` sobre `app.*`, sin acceso directo a las tablas).

---

## 7. Dar de alta una empresa nueva

Desde **Configuración → Sede → Nueva sede** (solo super admin), o por API
`POST /api/empresas`. Al crearla se aprovisionan su almacén principal y un primer
consultorio. Después hay que cargarle lo suyo, porque **no hereda nada** de las
demás: horario de atención, servicios, productos y usuarios. La taxonomía de
especies y razas sí la comparte.
