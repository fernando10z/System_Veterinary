# 001 — La lógica de negocio vive en stored procedures

## Contexto

`System_ERP` ya había tomado esta decisión y este ERP debía replicar su arquitectura.
La alternativa habitual (lógica en el backend, la base como almacén) es más común en
el ecosistema Node.

## Decisión

Toda regla de negocio se implementa en SPs de PostgreSQL bajo el schema `app`. El
backend valida la **forma** de la entrada (tipos, obligatoriedad) y delega la
validación **de negocio**.

## Consecuencias

**A favor**

- Las reglas no se pueden saltar desde otro cliente, un script de mantenimiento ni una
  integración futura: viven junto a los datos.
- Operaciones compuestas (emitir un comprobante marca órdenes de servicio como
  facturadas, descuenta stock y recalcula saldos) son atómicas sin coordinar
  transacciones desde la aplicación.
- Un SP se prueba con `psql` sin levantar el backend.
- El backend queda tan delgado que reescribirlo en otro lenguaje sería mecánico.

**En contra**

- Requiere saber PL/pgSQL, no solo TypeScript.
- Versionar SPs exige disciplina de migraciones: no hay "solo edito el archivo".
- El tooling (debugger, tipos) es más pobre que en TypeScript.

**Mitigaciones adoptadas**

- Convención uniforme `{ok, data, error, meta}` en todos los SPs, y un único executor
  que la desempaqueta y mapea a HTTP.
- Helpers en `internal` para lo repetitivo (acceso por sede, auditoría, correlativos,
  movimiento de stock).
- Migraciones idempotentes y numeradas, aplicadas en orden byte a byte.
