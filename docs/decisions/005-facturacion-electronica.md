# ADR-005 · La facturación electrónica entra por un adaptador

**Estado:** aceptada · **Fecha:** 2026-09-20

## Contexto

En el Perú la emisión electrónica es obligatoria: una veterinaria que cobra y no
emite ante SUNAT no puede operar. El ERP tenía los campos del comprobante
electrónico —`hash_cpe`, `xml_url`, `cdr_url`, `sunat_codigo`— y un endpoint
para cargar la respuesta a mano, pero ninguna forma de emitir. El dato existía;
el trámite, no.

La clínica trabaja con **The Factory HKA**, que recibe el comprobante en JSON,
arma el XML UBL 2.1, lo firma, lo envía a SUNAT y devuelve el CDR y el PDF. Es
un proveedor, no la única opción: el contrato se renegocia, el precio cambia y
la clínica puede mudarse a otro OSE sin avisar al equipo de desarrollo.

Además hay dos realidades que conviven en el mismo ERP: empresas que emiten
electrónicamente desde aquí y empresas que numeran y cobran aquí pero llevan su
talonario por fuera.

## Decisión

El sistema habla contra una interfaz, `PseAdapter`, y no contra The Factory HKA.

- `TheFactoryHkaAdapter` implementa el contrato real (`Autenticacion`, `Enviar`,
  `EstatusDocumento`, `ComunicacionBaja`, `DescargaArchivo`).
- `PseMockAdapter` es el modo por defecto (`PSE_MODE=sandbox`): no sale a la red
  y **rechaza lo que SUNAT también rechazaría**, para que el camino de error se
  pueda ejercitar sin tener credenciales.
- `PseService` orquesta: lee el comprobante, arma el payload, delega y persiste
  lo que volvió. No decide reglas de negocio.

Los **códigos de catálogo SUNAT se resuelven en el SP**, no en el backend: la
afectación al IGV de una línea (catálogo 07), su unidad de medida (catálogo 03)
y el tipo de documento del receptor (catálogo 06) son reglas de negocio, y las
reglas de negocio viven en la base ([ADR-001](001-logica-en-stored-procedures.md)).
El backend traduce a HTTP; no interpreta.

`core.empresas.emite_electronico` separa los dos casos. Una empresa con la
bandera apagada numera, cobra y reporta en el ERP, y sus comprobantes nunca
salen al PSE.

## Consecuencias

**A favor**

- Cambiar de proveedor es escribir un adaptador nuevo. Los SPs, el orquestador
  y la pantalla no se tocan.
- El flujo completo —emitir, enviar, aceptar, acreditar— se prueba en cualquier
  máquina sin credenciales ni salir a internet.
- Cada intento queda en `core.comprobante_pse_log` con request y response
  completos, incluso el fallido. Cuando SUNAT rechaza, el mensaje del proveedor
  es lo único que explica por qué, y días después ya no se puede reproducir el
  envío.
- Dos empresas del mismo ERP emiten cada una con su RUC, porque las credenciales
  viven por empresa y no en el ambiente.

**En contra**

- El payload de HKA tiene campos que otro proveedor nombra distinto. La
  interfaz los abstrae, pero el adaptador nuevo hay que escribirlo entero.
- El sandbox simula la aceptación; la homologación real contra SUNAT sigue
  siendo un paso manual que nadie puede automatizar desde acá.

## Alternativas descartadas

**Generar el XML UBL y firmarlo nosotros.** Es lo que hace el PSE, y hacerlo
implica mantener el certificado digital, seguir cada resolución de SUNAT que
cambia el esquema y responder por los rechazos. Una clínica veterinaria no
necesita esa superficie: contrata un PSE por mucho menos de lo que cuesta
mantenerla.

**Llamar a The Factory HKA directamente desde el servicio de facturación.** Es
menos código hoy. El día que la clínica cambie de proveedor —o el día que haya
que probar sin credenciales— hay que reescribir el módulo completo, incluidos
los caminos de error que nadie recuerda.

**Guardar las credenciales en variables de ambiente.** Funcionaría con una sola
empresa. Con dos, la segunda emitiría con el RUC de la primera, que es el error
más caro que puede cometer un ERP multi-empresa.
