/**
 * Abre una vista de impresión en pestaña nueva.
 *
 * En pestaña y no en la misma pantalla porque el mostrador imprime sin perder
 * lo que estaba haciendo: se imprime la receta y se sigue en la consulta.
 * `auto` dispara el diálogo de impresión al cargar, que es lo que se espera de
 * un botón que dice "Imprimir".
 */
export function abrirDocumento(tipo, id, { auto = false, ...params } = {}) {
  const qs = new URLSearchParams({ ...params, ...(auto ? { auto: "1" } : {}) });
  const cola = qs.toString();
  window.open(`/imprimir/${tipo}/${id}${cola ? `?${cola}` : ""}`, "_blank", "noopener");
}
