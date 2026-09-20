import { Logger, ServiceUnavailableException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import {
  PseAdapter,
  PseCredenciales,
  PseEnvioResult,
  PseEstadoResult,
  PseBajaResult,
  PseArchivoResult,
  ComprobantePayload,
} from "./pse-adapter.interface";

/**
 * Adaptador real contra la API REST de The Factory HKA Perú (servicio WCF
 * `ServiceClients.svc`). Contrato tomado del "Manual de Integración Directa –
 * REST" y verificado en producción por System_ERP.
 *
 * Flujo:
 *   1) Autenticacion    → {clave, ruc, tipoAplicacion:"I", usuario} → token JWT
 *   2) Enviar           → {documentoElectronico:{…}, ruc, token}    → codigo/mensaje
 *   3) EstatusDocumento → {documento, ruc, token}                   → estado SUNAT
 *
 * Semántica de la respuesta (catálogo de errores HKA):
 *   codigo === "0"  → éxito ("Comprobante Aprobado", "El CDR estará disponible…")
 *   cualquier otro  → error (200 RUC inexistente, 203 credenciales, 206 serie
 *                     inexistente, 207 numeración ya existe, 202 ya procesado…)
 *
 * El identificador de documento en HKA es "RUC-CodTipoDoc-Serie-Correlativo".
 */
export class TheFactoryHkaAdapter implements PseAdapter {
  readonly nombre = "the_factory_hka";
  private readonly logger = new Logger(TheFactoryHkaAdapter.name);

  constructor(private readonly config: ConfigService) {}

  /** Código SUNAT de tipo de documento (catálogo 01). */
  private static readonly COD_TIPO: Record<string, string> = {
    factura: "01",
    boleta: "03",
    nota_credito: "07",
    nota_debito: "08",
  };

  private timeoutMs(): number {
    return this.config.get<number>("pse.timeoutMs") ?? 15000;
  }

  /**
   * Base del servicio: se le quita el sufijo `/help` (la página de ayuda del
   * WCF) y las barras finales, para poder anexar `/Autenticacion`, `/Enviar`…
   */
  private baseUrl(cred: PseCredenciales): string {
    let url = (cred.endpoint || this.config.get<string>("pse.endpoint") || "").trim();
    url = url.replace(/\/help\/?$/i, "").replace(/\/+$/, "");
    if (!url) {
      throw new ServiceUnavailableException(
        "Falta el endpoint de The Factory HKA. Configúralo en Configuración → Empresa.",
      );
    }
    return url;
  }

  private async post(base: string, op: string, body: unknown): Promise<any> {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), this.timeoutMs());
    try {
      const resp = await fetch(`${base}/${op}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(body),
        signal: ctrl.signal,
      });
      const text = await resp.text();
      let json: any = {};
      try {
        json = text ? JSON.parse(text) : {};
      } catch {
        // El WCF devuelve HTML ante un error de ruta.
        this.logger.warn(`HKA ${op}: respuesta no-JSON (HTTP ${resp.status}): ${text.slice(0, 200)}`);
        throw new ServiceUnavailableException(
          `The Factory HKA devolvió una respuesta inesperada (HTTP ${resp.status}).`,
        );
      }
      if (resp.status < 200 || resp.status >= 300) {
        this.logger.warn(`HKA ${op} HTTP ${resp.status}: ${JSON.stringify(json).slice(0, 300)}`);
      }
      return json;
    } catch (e: any) {
      if (e instanceof ServiceUnavailableException) throw e;
      this.logger.error(`The Factory HKA (${op}) no respondió: ${e?.message}`);
      throw new ServiceUnavailableException(
        "El proveedor de facturación no respondió. Reintenta en unos minutos.",
      );
    } finally {
      clearTimeout(timer);
    }
  }

  private async autenticar(cred: PseCredenciales): Promise<string> {
    const base = this.baseUrl(cred);
    const json = await this.post(base, "Autenticacion", {
      clave: cred.password,
      ruc: cred.ruc,
      tipoAplicacion: "I",
      usuario: cred.usuario,
    });
    if (json?.codigo !== "0" || !json?.token) {
      throw new ServiceUnavailableException(
        `No se pudo autenticar con The Factory HKA (${json?.codigo ?? "?"}): ${
          json?.mensaje ?? "sin detalle"
        }`,
      );
    }
    return String(json.token);
  }

  private num(v: number | undefined | null, dec = 2): string {
    return Number(v ?? 0).toFixed(dec);
  }

  /** Identificador SUNAT del documento: RUC-CodTipo-Serie-Correlativo. */
  private documentoId(p: ComprobantePayload): string {
    const cod = TheFactoryHkaAdapter.COD_TIPO[p.tipoDocumento];
    return `${p.empresa.ruc}-${cod}-${p.serie}-${p.numero}`;
  }

  /** Arma el nodo `documentoElectronico` de HKA a partir del comprobante. */
  private buildDocumento(p: ComprobantePayload): Record<string, unknown> {
    const cod = TheFactoryHkaAdapter.COD_TIPO[p.tipoDocumento];
    const esExtranjera = (p.moneda ?? "PEN") !== "PEN";

    const producto = p.items.map((it, i) => {
      const cant = Number(it.cantidad ?? 1) || 1;
      const valorUnitarioBI = it.subtotal / cant;
      const precioVentaUnit = it.total / cant;
      return {
        numeroOrden: String(i + 1),
        unidadMedida: it.unidadMedida || "NIU",
        descripcion: it.descripcion,
        codigoPLU: it.codigo || undefined,
        cantidad: this.num(cant, 6),
        valorUnitarioBI: this.num(valorUnitarioBI, 6),
        valorReferencialUnitario: this.num(valorUnitarioBI, 6),
        precioVentaUnitarioItem: this.num(precioVentaUnit, 6),
        valorVentaItemQxBI: this.num(it.subtotal, 2),
        montoTotalImpuestoItem: this.num(it.igv, 2),
        IGV: {
          porcentaje: this.num(it.igvPorcentaje ?? 18, 2),
          tipo: it.tipoAfectacionIgv || "10",
          monto: this.num(it.igv, 2),
          baseImponible: this.num(it.subtotal, 2),
        },
      };
    });

    const pago: Record<string, unknown> = {
      fechaInicio: p.fechaEmision || undefined,
      fechaFin: p.fechaVencimiento || p.fechaEmision || undefined,
      moneda: p.moneda || "PEN",
    };
    if (esExtranjera) pago.tipoCambio = this.num(p.tipoCambio ?? 1, 3);

    // Al contado basta con declarar la forma de pago; al crédito hay que mandar
    // el cronograma y que cuadre con el neto pendiente.
    const facturaNegociable = p.formaPago
      ? {
          modoPago: p.formaPago.tipo,
          montoNetoPendiente:
            p.formaPago.tipo === "Credito"
              ? this.num(p.formaPago.montoNetoPendiente, 2)
              : undefined,
          cuotasFactura:
            p.formaPago.tipo === "Credito" && p.formaPago.cuotas?.length
              ? p.formaPago.cuotas.map((c) => ({
                  identificadorCuota: c.id,
                  fechaPagoCuota: c.fecha,
                  montoPagoCuota: this.num(c.monto, 2),
                }))
              : undefined,
        }
      : undefined;

    return {
      emisor: {
        ruc: p.empresa.ruc,
        nombreComercial: p.empresa.nombreComercial || p.empresa.razonSocial,
        lugarExpedicion: "0000",
        domicilioFiscal: p.empresa.domicilioFiscal || "",
        urbanizacion: p.empresa.urbanizacion || "",
        distrito: p.empresa.distrito || "",
        provincia: p.empresa.provincia || "",
        departamento: p.empresa.departamento || "",
        codigoPais: "PE",
        ubigeo: p.empresa.ubigeo || "",
      },
      receptor: {
        tipoDocumento: p.cliente.tipoDoc || "1",
        numDocumento: p.cliente.numeroDoc || "",
        razonSocial: p.cliente.razonSocial || "",
        direccion: p.cliente.direccion || "",
        pais: p.cliente.pais || "PE",
        ubigeo: p.cliente.ubigeo || undefined,
        notificar: p.cliente.email ? "SI" : "NO",
        email: p.cliente.email || "",
      },
      fechaEmision: p.fechaEmision || undefined,
      horaEmision: p.horaEmision || undefined,
      fechaVencimiento: p.fechaVencimiento || undefined,
      tipoDocumento: cod,
      serie: p.serie,
      correlativo: String(p.numero),
      // Catálogo SUNAT 51. La clínica sólo hace venta interna.
      codigoTipoOperacion: "0101",
      relacionadoNotas:
        (p.tipoDocumento === "nota_credito" || p.tipoDocumento === "nota_debito") && p.referencia
          ? {
              tipoDocAfectado: p.referencia.tipoDocAfectado,
              numeroDocAfectado: p.referencia.numeroDocAfectado,
              codigoTipoNota: p.referencia.codigoTipoNota,
              observaciones: p.referencia.observaciones,
            }
          : undefined,
      producto,
      facturaNegociable,
      totales: {
        sumaTotalDescuentosporItem: "",
        subtotalValorVenta: this.num(p.totales.gravado, 2),
        totalIGV: this.num(p.totales.igv, 2),
        montoTotalImpuestos: this.num(p.totales.igv, 2),
        importeTotalVenta: this.num(p.totales.total, 2),
        importeTotalPagar: this.num(p.totales.total, 2),
        subtotal: {
          IGV: this.num(p.totales.gravado, 2),
          exoneradas: p.totales.exonerado ? this.num(p.totales.exonerado, 2) : "",
          inafectas: p.totales.inafecto ? this.num(p.totales.inafecto, 2) : "",
        },
      },
      pago,
      // SUNAT limita la línea adicional a 100 caracteres (error 113).
      lineasAdicionales: p.observaciones
        ? [{ codigo: "2006", valor: p.observaciones.slice(0, 100) }]
        : [],
    };
  }

  async enviarComprobante(
    payload: ComprobantePayload,
    cred: PseCredenciales,
  ): Promise<PseEnvioResult> {
    const token = await this.autenticar(cred);
    const base = this.baseUrl(cred);
    const documento = this.documentoId(payload);
    const json = await this.post(base, "Enviar", {
      documentoElectronico: this.buildDocumento(payload),
      ruc: cred.ruc,
      token,
    });

    const codigo = String(json?.codigo ?? "");
    const mensaje = json?.mensaje ?? null;
    if (codigo !== "0") {
      return {
        requestId: documento,
        aceptado: false,
        estadoFinal: "rechazado_sunat",
        codigoSunat: codigo || null,
        mensajeSunat: mensaje,
        raw: json,
      };
    }

    // Numeración REAL asignada por HKA ("CodTipo-Serie-Correlativo"). En series
    // de asignación automática puede diferir de la que mandó el ERP, y es la
    // que sirve para consultar el estado y bajar el CDR.
    const numeracion = json?.numeracion ? String(json.numeracion) : null;
    const requestId = numeracion ? `${cred.ruc}-${numeracion}` : documento;

    // HKA lo aceptó; el CDR de SUNAT llega en minutos.
    return {
      requestId,
      aceptado: false,
      estadoFinal: "enviado_sunat",
      codigoSunat: codigo,
      mensajeSunat: mensaje,
      xmlPath: json?.nombreXML ?? json?.rutaXML ?? null,
      cdrPath: json?.nombreCDR ?? json?.rutaCDR ?? null,
      pdfPath: json?.nombrePDF ?? json?.rutaPDF ?? null,
      raw: json,
    };
  }

  async consultarEstado(requestId: string, cred: PseCredenciales): Promise<PseEstadoResult> {
    const token = await this.autenticar(cred);
    const base = this.baseUrl(cred);
    const json = await this.post(base, "EstatusDocumento", {
      documento: requestId,
      ruc: cred.ruc,
      token,
    });
    const codigo = String(json?.codigo ?? "");
    const mensaje: string = json?.mensaje ?? "";
    let estadoFinal: PseEstadoResult["estadoFinal"] = "enviado_sunat";
    if (codigo === "0") {
      estadoFinal = /observ/i.test(mensaje) ? "observado_sunat" : "aceptado_sunat";
    } else if (/rechaz/i.test(mensaje)) {
      estadoFinal = "rechazado_sunat";
    }
    return { estadoFinal, codigoSunat: codigo || null, mensajeSunat: mensaje || null, raw: json };
  }

  async comunicarBaja(
    documento: string,
    motivo: string,
    cred: PseCredenciales,
  ): Promise<PseBajaResult> {
    const token = await this.autenticar(cred);
    const base = this.baseUrl(cred);
    const json = await this.post(base, "ComunicacionBaja", {
      documento,
      motivo,
      ruc: cred.ruc,
      token,
    });
    const codigo = String(json?.codigo ?? "");
    return {
      aceptado: codigo === "0",
      codigo: codigo || null,
      mensaje: json?.mensaje ?? null,
      raw: json,
    };
  }

  async descargarArchivo(
    documento: string,
    tipo: "XML" | "PDF" | "CDR",
    cred: PseCredenciales,
  ): Promise<PseArchivoResult> {
    const token = await this.autenticar(cred);
    const base = this.baseUrl(cred);
    const json = await this.post(base, "DescargaArchivo", {
      documento,
      tipoArchivo: tipo,
      ruc: cred.ruc,
      token,
    });
    const codigo = String(json?.codigo ?? "");
    return {
      contenidoBase64: json?.archivo ?? json?.contenido ?? null,
      codigo: codigo || null,
      mensaje: json?.mensaje ?? null,
      raw: json,
    };
  }
}
