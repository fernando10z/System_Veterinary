# ADR-008 · El dinero y el stock no dependen de que nadie pulse a la vez

**Estado:** aceptada · **Fecha:** 2026-09-27

## Contexto

La suite de `verificar-api.sh` hace una llamada cada vez, así que nunca iba a
ver una carrera. Una clínica, en cambio, tiene dos o tres personas en el
mostrador a la misma hora. Una revisión con esa mirada encontró tres clases de
problemas. Ninguno se veía en las pruebas y todos salían al atacar con llamadas
simultáneas (`scripts/verificar-concurrencia.sh` contra el código anterior):

1. **Carreras.** Dos emisiones simultáneas para el mismo propietario facturaron
   la misma consulta tres veces. El mismo hueco de agenda se reservó cinco
   veces. Un plan con una consulta incluida cubrió cinco. Lo mismo podía pasar
   con el último frasco del almacén, con dos cobros sobre el mismo saldo y con
   dos notas de crédito parciales sobre la misma línea.
2. **El saldo tenía dos fórmulas.** El trigger de ítems y
   `recalcular_saldo_comprobante` calculaban el saldo cada uno a su manera, y
   ninguno restaba las notas de crédito. La nota bajaba el saldo a mano y el
   siguiente cobro lo pisaba: una factura de 100 con una nota de 30 y un cobro
   de 70 volvía a deber 30.
3. **Descuadres ante SUNAT.** El descuento global se restaba solo al total, y
   quedaba total ≠ base + IGV. La nota de crédito de una boleta salía con serie
   F. Las líneas cubiertas al 100 % por el plan iban como gravadas con valor
   cero. Una baja aceptada por SUNAT no podía reflejarse en el ERP porque pasaba
   por `sp_comprobante_anular`, que rechaza todo lo enviado.

## Decisión

### Cada recurso disputado tiene un candado explícito, en la base

| Qué se disputa | Candado | Dónde |
|---|---|---|
| Lo pendiente de un propietario | `FOR UPDATE` sobre el cliente | `sp_comprobante_emitir` |
| El saldo de un comprobante | `FOR UPDATE` sobre el comprobante | cobro, nota de crédito, anulación |
| El stock de un almacén | `FOR UPDATE` sobre la fila de `stock` y los lotes | `internal.mover_stock` |
| La agenda de un veterinario | `pg_advisory_xact_lock` por veterinario | `internal.bloquear_agenda` |
| El cupo de un plan | `FOR UPDATE` sobre la suscripción | `internal.registrar_cargo_servicio` |
| La caja | `FOR SHARE` al cobrar, `FOR UPDATE` al cerrar | pagos y `sp_caja_cerrar` |
| El envío a SUNAT | reserva con `envio_en_curso_at` (caduca a los 2 min) | `sp_comprobante_reservar_envio` |

Los candados viven donde vive la regla ([ADR-001](001-logica-en-stored-procedures.md)).
Un mutex en el backend no protegería a una segunda instancia de PM2, ni a un
script que llame al SP directamente.

**Por qué candados y no `SERIALIZABLE`.** Con aislamiento serializable, el
perdedor recibe un `40001` y alguien tiene que reintentar. Eso es otro código
en cada llamada, y un cajero que ve "reintenta" sin saber por qué. El candado
hace esperar al segundo unos milisegundos y luego le da una respuesta de
negocio con sentido: "ya fue facturado", "stock insuficiente", "el veterinario
ya tiene una cita en ese horario". Si aun así dos transacciones se cruzan
(deadlock), el backend traduce `40P01` a un 409 con "vuelve a intentarlo".

### Las restricciones son la segunda línea

`CHECK (cantidad >= 0)` en `stock` y `lotes`, montos positivos en las
aplicaciones de pago y líneas coherentes en los comprobantes. Si mañana un SP
nuevo olvida el candado, la base rechaza el estado imposible en vez de
guardarlo.

El trigger de stock hace `UPDATE` antes que `INSERT`. Un `INSERT … ON CONFLICT`
con delta negativo choca con el `CHECK` antes de llegar al conflicto, porque
Postgres valida la fila propuesta y no la resultante.

### Idempotencia en lo que numera o cobra

`comprobantes.idempotency_key` y `pagos.idempotency_key` llevan una clave que
genera el cliente, una por intento. El doble clic, el reintento tras un timeout
y la pestaña duplicada mandan la misma clave y reciben el mismo documento, con
`meta.repetido = true`. El número de operación de Yape/Plin/transferencia es
único por empresa y medio: el mismo voucher no entra dos veces.

### Una sola fórmula del saldo

```
saldo = total − cobros vigentes − notas de crédito vigentes que lo corrigen
```

Vive en `internal.recalcular_saldo_comprobante` y todos la llaman: el trigger
de ítems, el cobro, la anulación del cobro, la nota de crédito y la anulación.
Una nota de crédito y un comprobante anulado tienen siempre saldo cero. El
saldo sale de los hechos, no de la historia de quién lo tocó antes.

### SUNAT

- El descuento global **se prorratea en las líneas** al emitir. La cabecera es
  la suma de las líneas, y la línea lleva su base e IGV ya descontados.
- La serie se valida contra el tipo (`F…` factura, `B…` boleta) y sale de la
  **sede** donde se emite. La nota de crédito toma la letra del documento que
  corrige.
- Una línea en cero no va al XML. Una factura o boleta con total cero no se
  emite: lo que el plan cubre entero se documenta con nota de venta.
- La fecha de emisión no puede ser futura, ni más antigua de 3 días en una
  empresa que emite electrónicamente.
- La baja tiene su propia puerta, `sp_comprobante_registrar_baja`. El backend
  la llama dos veces: antes de hablar con SUNAT (¿procede? 7 días, sin cobros,
  sin nota) y después, para revertir.
- `recibir_respuesta` no revive un anulado ni hace retroceder un aceptado.

**Anular algo que aún no se envió sigue permitido.** SUNAT valida que un número
no se repita, no que la serie no tenga huecos. Obligar a enviar y dar de baja
un comprobante que nunca debió existir cuesta más que el hueco. Lo que SUNAT
ya recibió se corrige con nota de crédito o con baja.

### La cuota del plan también se cobra

Un plan que regala consultas y no cobra su cuota es un descuento disfrazado. La
primera cuota se carga al contratar. Las siguientes las carga
`app.sp_tareas_diarias`, que el backend ejecuta a las 5:00 (hora de Lima) y al
arrancar, junto con el vencimiento de los planes. Si se anula una orden, el
cupo del plan que había consumido vuelve (trigger sobre `ordenes_servicio`).

## Consecuencias

- `scripts/verificar-concurrencia.sh` se ejecuta en la CI. Contra el código
  anterior falla en 5 de 13 comprobaciones; contra este, en ninguna.
- El frontend genera una `idempotency_key` por intento de emisión y de cobro.
  Un cliente que no la mande sigue funcionando, pero sin esa protección.
- Un Yape, Plin, transferencia o depósito exige número de operación.
- Cerrar una caja con diferencia exige una observación.
- **Límite conocido:** los lotes no son por almacén. El stock sí lo es, así que
  una clínica con varios locales ve bien cuántas unidades hay en cada uno, pero
  FEFO elige el lote entre todos los locales. Separarlo pide `almacen_id` en
  `lotes` y trasladar lotes en las transferencias. Queda para cuando una
  clínica multi-sede trabaje con lotes.
