# Visión general

## El principio

La lógica de negocio vive en **stored procedures de PostgreSQL**. El backend no
inventa reglas: valida la forma de la entrada, resuelve quién está pidiendo y llama al
SP. Esto se hereda de `System_ERP` y tiene una consecuencia concreta: las reglas
clínicas y contables no se pueden saltar desde otro cliente, un script o una
integración futura, porque viven junto a los datos.

## Recorrido de una petición

```
Navegador
   │  fetch con Bearer token
   ▼
apiFetch (frontend)            adjunta token, renueva el access si expiró
   │
   ▼
JwtAuthGuard                   verifica firma, issuer y audience
   │
   ▼
ValidationPipe + DTO           forma y tipos; mensajes en español
   │
   ▼
Controller → Service           arma SpContext = {userId, empresaId, isSuperAdmin}
   │
   ▼
Repository                     único lugar que nombra SPs
   │
   ▼
SpExecutorService              SELECT app.sp_x($1,$2,…)
   │
   ▼
PostgreSQL                     ── reglas de negocio, permisos, auditoría ──
   │
   ▼
{ok, data, error, meta}        el executor desempaqueta y mapea el error a HTTP
```

## Por qué el backend es delgado

Un backend que también valida reglas termina con dos fuentes de verdad que se
desincronizan. Aquí la única validación del backend es **estructural** (¿el campo es
un UUID? ¿el monto es positivo?). La validación **de negocio** (¿este veterinario
puede firmar? ¿queda stock? ¿el cliente tiene RUC para factura?) es del SP.

Eso permite que un SP se pruebe con `psql` sin levantar el backend, y que la respuesta
sea idéntica venga de donde venga la llamada.

## Aislamiento entre empresas

Cada empresa es un negocio independiente. El backend nunca decide qué empresa ve un
usuario: propaga `(user_id, empresa_id, is_super_admin)` y el SP decide con
`internal.es_acceso_global`. Un bug en el frontend no puede filtrar datos de otra
empresa, porque el filtro está en la consulta, no en la vista.

En **escritura** hay dos reglas, y ambas hacen falta:

1. **La empresa se toma del contexto**, o se hereda del registro padre. Nunca del
   payload: aceptarla del cliente sería dejar que elija dónde escribir.
2. **Todo SP que recibe el id de un registro comprueba a quién pertenece**, con
   `internal.es_de_empresa(...)`.

La segunda no es redundante. Un administrador de empresa tiene el permiso
`facturacion:anular` legítimamente, y si el SP solo verifica el permiso, anularía el
comprobante de otra empresa con solo conocer su UUID: el permiso lo tiene y el
registro existe. Falta preguntar *de quién es*.

Cuando la comprobación falla se responde `NOT_FOUND`, no `FORBIDDEN`: un `403`
confirmaría que el registro existe en otra empresa, que ya es información.

## Dos autenticaciones separadas

El backoffice y el portal del propietario emiten tokens con **issuer y audience
distintos**, y el token del portal lleva `type: "portal"`. No es cosmético: significa
que un token del portal falla la verificación del guard del staff y viceversa. Los SPs
del portal reciben `cliente_id`, nunca un `user_id`, y solo devuelven lo asociado a
ese propietario.

## Historia clínica como línea de tiempo

Cada acto clínico —consulta, vacuna, cirugía, hospitalización, examen, nota— registra
un evento en `core.historia_clinica` a través de
`internal.registrar_evento_clinico`. Armar el historial de un paciente es entonces un
`SELECT … ORDER BY fecha DESC`, no seis consultas mezcladas en el cliente. Y como la
tabla lleva `empresa_id`, **cada empresa ve solo los eventos que registró**: la
historia clínica no cruza negocios independientes.

## Una sola puerta al inventario

Todo movimiento de stock pasa por `internal.mover_stock`, que valida existencias e
inserta en `core.movimientos_inventario`. Un trigger ajusta `core.stock`, el lote y el
denormalizado `productos.stock_actual`. Nadie escribe stock directamente: por eso el
kardex y el saldo no pueden descuadrar.
