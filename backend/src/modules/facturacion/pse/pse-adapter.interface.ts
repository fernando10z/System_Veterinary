/**
 * Frontera del proveedor de facturación electrónica (PSE/OSE).
 *
 * El resto del sistema habla contra esta interfaz, no contra The Factory HKA:
 * así el sandbox y el proveedor real son intercambiables, y cambiar de
 * proveedor mañana no toca el orquestador ni los SPs.
 */

export interface PseCredenciales {
  endpoint: string;
  usuario: string;
  /** Clave YA descifrada por el servicio (nunca el blob cifrado). */
  password: string;
  /** RUC del emisor: The Factory HKA lo exige en cada llamada. */
  ruc: string;
}

/**
 * Comprobante normalizado que se le entrega al adaptador. Trae todo lo que
 * necesita el `documentoElectronico` de HKA (UBL 2.1); los códigos de catálogo
 * SUNAT ya vienen resueltos desde el SP, no se deciden aquí.
 */
export interface ComprobantePayload {
  empresa: {
    ruc: string;
    razonSocial: string;
    nombreComercial?: string | null;
    ubigeo?: string | null;
    domicilioFiscal?: string | null;
    urbanizacion?: string | null;
    distrito?: string | null;
    provincia?: string | null;
    departamento?: string | null;
  };
  tipoDocumento: "factura" | "boleta" | "nota_credito" | "nota_debito";
  serie: string;
  numero: number;
  /** YYYY-MM-DD */
  fechaEmision?: string | null;
  /** HH:mm:ss */
  horaEmision?: string | null;
  fechaVencimiento?: string | null;
  moneda: string;
  tipoCambio: number;
  /**
   * Forma de pago (cbc:PaymentTerms). SUNAT la exige en toda factura: al
   * contado, o al crédito con su cronograma. La suma de las cuotas tiene que
   * cuadrar con el neto pendiente o el documento se rechaza.
   */
  formaPago?: {
    tipo: "Contado" | "Credito";
    montoNetoPendiente?: number;
    cuotas?: Array<{ id: string; fecha: string; monto: number }>;
  } | null;
  cliente: {
    /** Catálogo SUNAT 06 ya resuelto: "1" DNI, "4" CE, "6" RUC, "7" pasaporte. */
    tipoDoc: string | null;
    numeroDoc: string | null;
    razonSocial: string | null;
    direccion: string | null;
    ubigeo?: string | null;
    pais?: string | null;
    email?: string | null;
  };
  totales: {
    gravado: number;
    exonerado?: number;
    inafecto?: number;
    descuentoGlobal?: number;
    igv: number;
    total: number;
  };
  /**
   * Documento afectado. SUNAT lo exige en toda nota de crédito o débito: sin
   * él no hay forma de saber qué comprobante se está corrigiendo.
   */
  referencia?: {
    /** Código SUNAT del afectado: "01" factura, "03" boleta. */
    tipoDocAfectado: string;
    /** Serie-correlativo tal como se emitió, p. ej. "B001-00000012". */
    numeroDocAfectado: string;
    /** Catálogo 09 (crédito) / 10 (débito). */
    codigoTipoNota: string;
    observaciones: string;
  } | null;
  items: Array<{
    descripcion: string;
    codigo?: string | null;
    /** Catálogo SUNAT 03: NIU producto, ZZ servicio. */
    unidadMedida?: string | null;
    cantidad: number;
    precioUnitario: number;
    /** Catálogo SUNAT 07: "10" gravado, "20" exonerado. */
    tipoAfectacionIgv: string;
    igvPorcentaje?: number;
    subtotal: number;
    igv: number;
    total: number;
  }>;
  observaciones?: string | null;
}

/** Estados en los que puede quedar un comprobante tras hablar con el PSE. */
export type EstadoPse =
  | "enviado_sunat"
  | "aceptado_sunat"
  | "observado_sunat"
  | "rechazado_sunat";

export interface PseEnvioResult {
  /** Identificador con el que el proveedor rastrea el documento. */
  requestId: string;
  /** true si SUNAT ya devolvió un CDR conforme. */
  aceptado: boolean;
  estadoFinal: EstadoPse;
  codigoSunat?: string | null;
  mensajeSunat?: string | null;
  xmlPath?: string | null;
  cdrPath?: string | null;
  pdfPath?: string | null;
  /** Respuesta cruda del proveedor; se persiste para poder auditarla. */
  raw?: unknown;
}

export interface PseEstadoResult {
  estadoFinal: EstadoPse;
  codigoSunat?: string | null;
  mensajeSunat?: string | null;
  raw?: unknown;
}

export interface PseBajaResult {
  aceptado: boolean;
  codigo?: string | null;
  mensaje?: string | null;
  raw?: unknown;
}

export interface PseArchivoResult {
  /** Contenido del archivo en base64 (XML, PDF o CDR). */
  contenidoBase64?: string | null;
  codigo?: string | null;
  mensaje?: string | null;
  raw?: unknown;
}

export interface PseAdapter {
  /** Nombre del proveedor, para los logs. */
  readonly nombre: string;
  enviarComprobante(payload: ComprobantePayload, cred: PseCredenciales): Promise<PseEnvioResult>;
  consultarEstado(requestId: string, cred: PseCredenciales): Promise<PseEstadoResult>;
  comunicarBaja?(documento: string, motivo: string, cred: PseCredenciales): Promise<PseBajaResult>;
  descargarArchivo?(
    documento: string,
    tipo: "XML" | "PDF" | "CDR",
    cred: PseCredenciales,
  ): Promise<PseArchivoResult>;
}
