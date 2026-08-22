/**
 * Serializa un valor que va a un parámetro `jsonb` de un SP.
 *
 * node-postgres convierte los ARRAYS de JavaScript a arrays de Postgres
 * (`{...}`), no a JSON. Al llegar a un parámetro jsonb eso explota con
 * "invalid input syntax for type json" —o peor, un `[]` vacío llega como el
 * objeto `{}` y revienta recién dentro del SP con "cannot extract elements from
 * an object"—. Los objetos planos sí se serializan bien, por eso el bug solo
 * aparece con listas (items, aplicaciones, etc.).
 *
 * Pasar el JSON ya serializado como texto funciona siempre: Postgres lo castea
 * al tipo jsonb del parámetro.
 *
 * OJO 1: usar solo para parámetros jsonb. Un parámetro de tipo array nativo
 * (uuid[], text[]) debe recibir el array de JS tal cual.
 *
 * OJO 2: NO envolver un null que el SP interpreta como "sin valor".
 * `jsonbArg(null)` devuelve el string "null", que castea al jsonb `'null'` —y
 * `'null'::jsonb IS NULL` es false—, así que el SP tomaría el camino equivocado.
 * En esos casos: `valor == null ? null : jsonbArg(valor)`.
 */
export function jsonbArg(value: unknown): string {
  return JSON.stringify(value ?? null);
}
