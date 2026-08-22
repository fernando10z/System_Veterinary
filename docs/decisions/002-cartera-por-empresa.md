# 002 — Cada empresa tiene su propia cartera

## Contexto

El ERP es multi-empresa. La pregunta era si propietarios y pacientes se comparten
entre empresas o pertenecen a una.

La primera implementación los hizo globales, copiando el criterio de `System_ERP`
(donde `core.customers` es "cartera global"). Ese criterio asume que las empresas
son del **mismo dueño** —un grupo con varias razones sociales, o una cadena con
sucursales—, y ahí compartir la cartera es una ventaja: el cliente que va a otro
local llega con su historia.

Al confirmar el alcance quedó claro que las empresas son **negocios
independientes**. Compartir la cartera dejaba de ser una ventaja y pasaba a ser
una fuga: la empresa B vería los clientes de la empresa A.

## Decisión

`core.clientes` y `core.mascotas` llevan `empresa_id NOT NULL` y viven en
`04_tables_per_empresa.sql`. Toda lectura filtra por empresa y toda escritura fija
la empresa desde el contexto del usuario, nunca desde el payload.

Consecuencias directas en el modelo:

- El documento del propietario es único **por empresa**:
  `UNIQUE (empresa_id, tipo_documento, numero_documento)`. La misma persona puede
  ser cliente de dos empresas, con una ficha distinta en cada una.
- El microchip también es único por empresa, por la misma razón.
- `mascotas.empresa_id` se hereda del propietario dentro del SP: una mascota no
  puede quedar en una empresa distinta a la de su dueño.
- La historia clínica no cruza empresas. Cada una ve solo los eventos que registró.

## Qué sigue siendo compartido, y por qué

| Tabla | Motivo |
|---|---|
| `empresas`, `roles`, `permisos`, `rol_permisos` | Son el modelo de identidad del sistema, no dato de negocio. |
| `especies`, `razas`, `especializaciones` | Taxonomía de referencia ("Canino", "Labrador", "Cirugía"). Duplicarla en cada empresa sería redundante y no contiene información sensible. |

La taxonomía **solo la edita el super admin**, que es el operador del ERP, no
ninguna de las empresas cliente. Sin esa restricción, el administrador de la
empresa A podría renombrar una especie que usa la empresa B: no sería una fuga de
datos, pero sí una escritura entre inquilinos.

## Consecuencias

**A favor**

- Aislamiento real, verificado con dos empresas y 39 intentos de acceso cruzado
  (lectura, edición, anulación, movimientos de stock y arqueo de caja): todos
  responden `NOT_FOUND`.

**Cómo se validó, y por qué importa**

La primera versión del aislamiento parecía correcta leyendo el código: las consultas
de listado filtraban por empresa. Un sondeo automatizado que intentaba usar los ids
de una empresa desde la otra encontró **11 fugas** que la lectura no reveló: los SPs
de mutación que reciben un id (`sp_comprobante_anular`, `sp_caja_cerrar`,
`sp_consulta_cerrar`, `sp_producto_eliminar`…) verificaban el permiso pero no la
pertenencia. Eran explotables con solo conocer un UUID.

De ahí sale la regla de `internal.es_de_empresa` y la costumbre de probar el
aislamiento con un sondeo, no leyendo los SELECT.
- Cada empresa administra su cartera sin coordinarse con las demás.
- El sistema sirve tanto para un grupo con varios negocios como para vender el ERP
  a varias clínicas sobre la misma instalación.

**En contra**

- Si dos empresas del mismo dueño quisieran compartir clientes, ahora habría que
  duplicarlos. Ese caso ya no está soportado.
- Un cliente que se atiende en dos empresas tiene dos historias clínicas separadas.
  Es lo correcto para negocios independientes, pero conviene decirlo: no hay una
  vista unificada del animal.

**Si más adelante hiciera falta soportar grupos de empresas**

Agregar `grupo_id` a `core.empresas` y cambiar el filtro de cartera de
`empresa_id = v_emp` a "empresas del mismo grupo". El cambio quedaría acotado a
`24_app_clientes.sql` y `25_app_mascotas.sql`, porque el filtro está en un solo
lugar por función.
