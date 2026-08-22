# 002 — Clientes y mascotas son globales; la atención es por sede

## Contexto

El ERP es multi-sede. Casi todas las tablas llevan `empresa_id`. La pregunta era qué
hacer con propietarios y pacientes.

## Decisión

`core.clientes` y `core.mascotas` **no** llevan `empresa_id` (solo
`empresa_origen_id`, informativo). Las citas, consultas, comprobantes e inventario sí.

## Consecuencias

**A favor**

- Un propietario que va a otra sede es el mismo registro: no hay que crearlo de nuevo
  ni reconciliar duplicados.
- La historia clínica sigue al paciente entre sedes, que es lo que un veterinario
  necesita al atender a un animal que viene de otra sucursal.
- El buscador de recepción encuentra a cualquier cliente de la cadena.

**En contra**

- Si en el futuro el sistema se vendiera a **cadenas distintas** en la misma base de
  datos, la cartera se mezclaría. Habría que agregar un nivel superior (`tenant_id`)
  por encima de `empresa_id`.
- Los indicadores de "clientes nuevos" son de la cadena, no de la sede.

**Nota de implementación**

Las lecturas que cruzan cartera con operación (deuda, última visita) sí filtran por
sede con `internal.es_acceso_global`, para que el personal de una sede vea la deuda
que le corresponde.
