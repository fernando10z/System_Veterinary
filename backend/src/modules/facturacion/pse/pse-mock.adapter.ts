import { Logger } from "@nestjs/common";
import {
  PseAdapter,
  PseCredenciales,
  PseEnvioResult,
  PseEstadoResult,
  PseBajaResult,
  ComprobantePayload,
} from "./pse-adapter.interface";

/**
 * Adaptador de sandbox. No sale a la red: simula que SUNAT aceptó el
 * comprobante y devuelve rutas ficticias de XML/CDR/PDF. Sirve para ejercitar
 * el flujo completo —emitir, enviar, aceptado, nota de crédito— antes de tener
 * credenciales de The Factory HKA.
 *
 * Rechaza a propósito los comprobantes que SUNAT también rechazaría, para que
 * el camino de error se pueda probar sin credenciales: una factura sin RUC del
 * receptor, o un comprobante sin ítems.
 */
export class PseMockAdapter implements PseAdapter {
  readonly nombre = "mock-sandbox";
  private readonly logger = new Logger(PseMockAdapter.name);

  async enviarComprobante(
    payload: ComprobantePayload,
    _cred: PseCredenciales,
  ): Promise<PseEnvioResult> {
    const id = `${payload.serie}-${String(payload.numero).padStart(8, "0")}`;
    const requestId = `${payload.empresa.ruc}-${id}`;

    if (!payload.items.length) {
      return {
        requestId,
        aceptado: false,
        estadoFinal: "rechazado_sunat",
        codigoSunat: "2027",
        mensajeSunat: "El comprobante no tiene ítems (SANDBOX)",
        raw: { sandbox: true },
      };
    }
    if (payload.tipoDocumento === "factura" && payload.cliente.tipoDoc !== "6") {
      return {
        requestId,
        aceptado: false,
        estadoFinal: "rechazado_sunat",
        codigoSunat: "2017",
        mensajeSunat: "Una factura exige RUC del adquiriente (SANDBOX)",
        raw: { sandbox: true },
      };
    }

    this.logger.log(`[SANDBOX] Simulando envío de ${id} a SUNAT (aceptado)`);
    const base = `sandbox/${payload.empresa.ruc}/${id}`;
    return {
      requestId,
      aceptado: true,
      estadoFinal: "aceptado_sunat",
      codigoSunat: "0",
      mensajeSunat: `El comprobante ${id} ha sido aceptado (SANDBOX)`,
      xmlPath: `${base}.xml`,
      cdrPath: `${base}-cdr.zip`,
      pdfPath: `${base}.pdf`,
      raw: { sandbox: true, payload },
    };
  }

  async consultarEstado(requestId: string, _cred: PseCredenciales): Promise<PseEstadoResult> {
    return {
      estadoFinal: "aceptado_sunat",
      codigoSunat: "0",
      mensajeSunat: `Comprobante ${requestId} aceptado (SANDBOX)`,
      raw: { sandbox: true },
    };
  }

  async comunicarBaja(
    documento: string,
    motivo: string,
    _cred: PseCredenciales,
  ): Promise<PseBajaResult> {
    this.logger.log(`[SANDBOX] Baja de ${documento}: ${motivo}`);
    return {
      aceptado: true,
      codigo: "0",
      mensaje: `Comunicación de baja de ${documento} aceptada (SANDBOX)`,
      raw: { sandbox: true },
    };
  }
}
