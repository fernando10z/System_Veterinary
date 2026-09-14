# ADR-004 · La normalización del dato vive en la base

**Estado:** aceptada · **Fecha:** 2026-08-22

## Contexto

En la clínica el mismo dato se escribe de muchas formas. El DNI llega como
`12345678`, `12.345.678` o `12-345.678`; el nombre como `JUAN PEREZ`, `juan
perez` o `  Juan   Perez `; el teléfono con paréntesis y guiones. En el sistema
legado eso producía duplicados: el mismo propietario cargado tres veces porque el
buscador no encontraba lo que ya existía.

El documento es **único por empresa** ([ADR-002](002-cartera-por-empresa.md)).
Esa restricción solo sirve si el valor guardado tiene una única forma posible.

## Decisión

La normalización se aplica con triggers `BEFORE INSERT OR UPDATE` en la base, no
en el backend ni en el formulario.

Consecuencia práctica: **cualquier** camino de escritura queda normalizado — un
SP, una carga masiva, un script de migración o un `UPDATE` manual en psql. No hay
puerta trasera por la que entre un dato sucio.

El backend hace un saneo previo (`SanearEntradaPipe`) por una razón distinta: la
validación del DTO corre antes de que el dato llegue a la base, y sin recortar
espacios rechazaría con «correo no válido» un correo que el sistema habría
guardado sin problema. Es ergonomía de formulario, no la fuente de verdad.

## Alternativas descartadas

**Normalizar en el frontend.** Se salta con cualquier cliente de API y no protege
las cargas masivas, que es justo donde entra la mayoría del dato sucio.

**Normalizar solo en los SPs.** Es la opción razonable de segundo lugar y de
hecho los SPs normalizan antes de validar. Pero deja fuera todo lo que no pasa
por un SP, y basta un script de migración descuidado para volver a duplicar.

**Normalizar al leer.** Rompe los índices: `WHERE normalizar(doc) = $1` no puede
usar el índice único, y la unicidad tendría que reimplementarse a mano.

## Costo asumido

El trigger corre en cada escritura. Es texto corto y funciones `IMMUTABLE`, así
que el costo es despreciable frente a la escritura misma.

Los datos que ya existían se normalizaron con un `UPDATE … SET id = id`
idempotente al final de la migración, que dispara el trigger sin cambiar nada
más.
