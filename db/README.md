# Base de datos — ERP Veterinario

PostgreSQL 16. Toda la lógica de negocio vive aquí, en stored procedures.

## Schemas

| Schema | Contenido | Accede el backend |
|---|---|---|
| `core` | Tablas, ENUMs y triggers | **No** |
| `app` | SPs y funciones públicas | **Sí** — única superficie |
| `internal` | Helpers privados reutilizados por los SPs | No |
| `audit` | Reservado para auditoría separada | No |

El rol `vet_app_user` (creado en `90_grants.sql`) solo tiene `USAGE` sobre `app` y
`EXECUTE` sobre sus funciones. No puede leer una tabla de `core` directamente: si un
SP no lo expone, el backend no lo ve.

## Orden de las migraciones

Se aplican en orden alfanumérico **byte a byte** (`LC_ALL=C`). El script fuerza ese
orden a propósito: con el locale del sistema, el glob ignora guiones bajos y puede
colar un archivo antes que otro del que depende.

| Rango | Contenido |
|---|---|
| `00`–`06` | Extensiones, schemas, ENUMs, tablas y triggers |
| `10` | Helpers de `internal` |
| `20`–`50` | SPs por dominio (auth, sedes, users, roles, clientes, mascotas, catálogos, citas, clínico, inventario, compras, facturación, pagos/caja, RRHH, dashboard, reportes, portal, auditoría) |
| `90` | Rol de aplicación y grants |
| `98`–`99` | Seeds base y datos de demostración |

## Convenciones

- **Nombres**: `app.fn_*` para lecturas (`STABLE`), `app.sp_*` para mutaciones.
- **Firma**: los SPs de contexto reciben `(p_user_id, p_empresa_id, p_is_super_admin, …)`.
- **Respuesta**: siempre `JSONB` con `{ok, data?, error?, meta?}`. Nunca lanzan al backend:
  capturan con `EXCEPTION WHEN OTHERS`.
- **Errores**: `internal.error_jsonb(code, message, field?)` con códigos que el backend
  mapea a HTTP (`NOT_FOUND`, `FORBIDDEN`, `CONFLICT`, `VALIDATION_ERROR`, `BUSINESS_RULE`).
- **Filtro de sede**: siempre
  `(internal.es_acceso_global(p_user_id, p_is_super_admin) OR x.empresa_id = v_emp)`.
- **Un solo nombre por función**: dos SPs con el mismo nombre y aridad hacen la llamada
  ambigua desde el backend (`function ... is not unique`).

## Scripts

```bash
bash db/scripts/apply-migrations.sh          # aplica todo, idempotente
ALLOW_RESET=yes bash db/scripts/reset-dev.sh # borra los schemas y reconstruye
bash db/scripts/backup.sh                    # dump comprimido con timestamp
bash db/scripts/restore.sh <archivo.dump>
```

Variables: `DB_HOST` `DB_PORT` `DB_USER` `DB_PASSWORD` `DB_NAME`. Los defaults apuntan
al compose de desarrollo (`localhost:5435/vet_demo`). Si el host no tiene `psql`, los
scripts usan el del contenedor `veterp_postgres_dev`.
