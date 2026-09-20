import { AsyncLocalStorage } from "async_hooks";

/**
 * Datos de la petición en curso, accesibles sin arrastrarlos por la firma de
 * cada método.
 *
 * Existe por la bitácora: `core.audit_log` tiene columnas `ip` y `user_agent`
 * desde el principio y siempre quedaban en NULL, porque quien inserta la fila
 * es `internal.registrar_auditoria` —dentro de la base— y el dato vive en el
 * request HTTP. Pasarlo como parámetro obligaría a cambiar la firma de los 174
 * SPs; el almacén asíncrono lo deja disponible en el único punto que lo
 * necesita: el ejecutor, justo antes de llamar al SP.
 */
export interface RequestContext {
  ip: string;
  userAgent: string;
  requestId: string;
}

const almacen = new AsyncLocalStorage<RequestContext>();

/** Fija el contexto para el resto de la cadena asíncrona de esta petición. */
export function iniciarContexto(ctx: RequestContext): void {
  almacen.enterWith(ctx);
}

export function contextoActual(): RequestContext | undefined {
  return almacen.getStore();
}
