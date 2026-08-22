import router from "../../router/index.js";

/**
 * Abre una ruta del ERP en una pestaña nueva.
 *
 * Se usa para los enlaces de referencia cruzada entre documentos (proforma
 * origen, contrato, comprobante): al revisar una factura o un contrato no se
 * quiere perder la pantalla actual para ir a ver el documento del que viene.
 */
export function abrirEnNuevaPestana(to) {
  if (!to) return;
  const { href } = router.resolve(to);
  window.open(href, "_blank", "noopener");
}
