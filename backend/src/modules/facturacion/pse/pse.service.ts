import { BadRequestException, Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { SpExecutorService } from "../../../infrastructure/database/sp-executor.service";
import { CryptoService } from "../../../infrastructure/crypto/crypto.service";
import { JwtPayload } from "../../../common/types/jwt-payload.type";
import { SpContext } from "../../../common/types/sp-result.type";
import { jsonbArg } from "../../../infrastructure/database/sp-args";
import {
  PseAdapter,
  ComprobantePayload,
  PseCredenciales,
  EstadoPse,
} from "./pse-adapter.interface";
import { PseMockAdapter } from "./pse-mock.adapter";
import { TheFactoryHkaAdapter } from "./the-factory-hka.adapter";

/** Datos fiscales del emisor que exige SUNAT en el comprobante. */
interface EmisorFiscal {
  ruc: string;
  razonSocial: string;
  nombreComercial?: string | null;
  ubigeo?: string | null;
  domicilioFiscal?: string | null;
  urbanizacion?: string | null;
  distrito?: string | null;
  provincia?: string | null;
  departamento?: string | null;
}

/**
 * Orquesta el envío de comprobantes al PSE.
 *
 * Reparto de responsabilidades, igual que en el resto del sistema: los SPs
 * deciden qué se puede enviar y guardan lo que volvió; este servicio sólo
 * traduce a HTTP. Por eso no hay ninguna regla de negocio escrita aquí que no
 * esté también en la base.
 */
@Injectable()
export class PseService {
  private readonly logger = new Logger(PseService.name);

  constructor(
    private readonly sp: SpExecutorService,
    private readonly config: ConfigService,
    private readonly crypto: CryptoService,
  ) {}

  private ctx(u: JwtPayload): SpContext {
    return { userId: u.sub, empresaId: u.empresa_id, isSuperAdmin: u.is_super_admin };
  }

  private get modoSandbox(): boolean {
    return (this.config.get<string>("pse.mode") ?? "sandbox") !== "real";
  }

  private adapter(): PseAdapter {
    return this.modoSandbox ? new PseMockAdapter() : new TheFactoryHkaAdapter(this.config);
  }

  private descifrarClave(passwordEnc?: string | null): string {
    if (!passwordEnc) return "";
    try {
      return this.crypto.decrypt(passwordEnc);
    } catch {
      this.logger.warn("No se pudo descifrar la clave del PSE (¿cambió ENCRYPTION_KEY?)");
      return "";
    }
  }

  /** Departamento según los dos primeros dígitos del ubigeo INEI. */
  private static readonly DEPARTAMENTO_POR_UBIGEO: Record<string, string> = {
    "01": "AMAZONAS", "02": "ANCASH", "03": "APURIMAC", "04": "AREQUIPA", "05": "AYACUCHO",
    "06": "CAJAMARCA", "07": "CALLAO", "08": "CUSCO", "09": "HUANCAVELICA", "10": "HUANUCO",
    "11": "ICA", "12": "JUNIN", "13": "LA LIBERTAD", "14": "LAMBAYEQUE", "15": "LIMA",
    "16": "LORETO", "17": "MADRE DE DIOS", "18": "MOQUEGUA", "19": "PASCO", "20": "PIURA",
    "21": "PUNO", "22": "SAN MARTIN", "23": "TACNA", "24": "TUMBES", "25": "UCAYALI",
  };

  /**
   * Completa departamento/provincia/distrito del emisor.
   *
   * SUNAT limita cada uno a 30 caracteres y rechaza con error 113 si se pasa.
   * La dirección fiscal suele terminar en "… DEPARTAMENTO - PROVINCIA -
   * DISTRITO", pero el departamento viene pegado a la calle, así que se deriva
   * del ubigeo —que es inequívoco— y el texto queda sólo como respaldo.
   */
  private completarUbigeo(cfg: any): Pick<
    EmisorFiscal,
    "distrito" | "provincia" | "departamento"
  > {
    const corta = (s?: string | null) => (s ? s.trim().slice(0, 30) || null : null);
    const porUbigeo =
      PseService.DEPARTAMENTO_POR_UBIGEO[String(cfg.ubigeo ?? "").trim().slice(0, 2)] ?? null;

    // Lo cargado a mano en Configuración → Empresa manda sobre lo deducido.
    if (cfg.departamento || cfg.provincia || cfg.distrito) {
      return {
        departamento: corta(cfg.departamento) ?? porUbigeo,
        provincia: corta(cfg.provincia),
        distrito: corta(cfg.distrito),
      };
    }

    const partes = String(cfg.direccion_fiscal ?? "")
      .split(" - ")
      .map((s) => s.trim())
      .filter(Boolean);
    if (partes.length < 3) return { departamento: porUbigeo, provincia: null, distrito: null };

    const [depTexto, prov, dist] = partes.slice(-3);
    const depFallback = depTexto.length <= 30 ? depTexto : null;
    return {
      departamento: porUbigeo ?? corta(depFallback),
      provincia: corta(prov),
      distrito: corta(dist),
    };
  }

  private async credenciales(
    ctx: SpContext,
    empresaId: string,
  ): Promise<{ cred: PseCredenciales; emisor: EmisorFiscal }> {
    const cfg = (await this.sp.callCtx<any>("app.fn_empresa_pse_config", ctx, [empresaId])) ?? {};
    const password = this.descifrarClave(cfg.password_enc);
    const ruc = cfg.ruc_pse ?? cfg.ruc ?? "";

    if (!this.modoSandbox && (!cfg.endpoint || !cfg.usuario || !password || !ruc)) {
      throw new BadRequestException(
        "Faltan credenciales de The Factory HKA (endpoint, usuario, clave o RUC). " +
          "Complétalas en Configuración → Empresa.",
      );
    }

    return {
      cred: { endpoint: cfg.endpoint ?? "", usuario: cfg.usuario ?? "", password, ruc },
      emisor: {
        ruc,
        razonSocial: cfg.razon_social ?? "",
        nombreComercial: cfg.nombre_comercial ?? null,
        ubigeo: cfg.ubigeo ?? null,
        domicilioFiscal: cfg.direccion_fiscal ?? null,
        urbanizacion: cfg.urbanizacion ?? null,
        ...this.completarUbigeo(cfg),
      },
    };
  }

  /**
   * Catálogo SUNAT 06: DNI→1, CE→4, RUC→6, pasaporte→7. Si el enum no coincide
   * se deduce por la longitud del número, para no dejar caer la emisión por un
   * dato mal tipeado.
   */
  private tipoDocSunat(enumVal?: string | null, numeroDoc?: string | null): string {
    const map: Record<string, string> = { DNI: "1", CE: "4", RUC: "6", PASAPORTE: "7" };
    if (enumVal && map[enumVal]) return map[enumVal];
    const n = (numeroDoc ?? "").replace(/\D/g, "");
    if (n.length === 11) return "6";
    if (n.length === 8) return "1";
    return "1";
  }

  private construirPayload(data: any, emisor: EmisorFiscal): ComprobantePayload {
    const c = data.comprobante ?? {};
    const items = (data.items ?? []) as any[];
    const esCredito = c.forma_pago === "credito";
    const total = Number(c.total ?? 0);

    return {
      empresa: {
        ruc: emisor.ruc,
        razonSocial: emisor.razonSocial,
        nombreComercial: emisor.nombreComercial,
        ubigeo: emisor.ubigeo,
        domicilioFiscal: emisor.domicilioFiscal,
        urbanizacion: emisor.urbanizacion,
        distrito: emisor.distrito,
        provincia: emisor.provincia,
        departamento: emisor.departamento,
      },
      tipoDocumento: c.tipo,
      serie: c.serie,
      numero: Number(c.numero),
      fechaEmision: c.fecha_emision ?? null,
      horaEmision: c.hora_emision ?? null,
      fechaVencimiento: c.fecha_vencimiento ?? null,
      moneda: c.moneda ?? "PEN",
      tipoCambio: Number(c.tipo_cambio ?? 1),
      // Una clínica pacta un vencimiento, no un cronograma partido: una cuota.
      formaPago: esCredito
        ? {
            tipo: "Credito",
            montoNetoPendiente: total,
            cuotas: c.fecha_vencimiento
              ? [{ id: "Cuota001", fecha: String(c.fecha_vencimiento).slice(0, 10), monto: total }]
              : [],
          }
        : { tipo: "Contado" },
      cliente: {
        tipoDoc: this.tipoDocSunat(c.cliente?.tipo_documento, c.cliente?.numero_documento),
        numeroDoc: c.cliente?.numero_documento ?? null,
        razonSocial: c.cliente?.razon_social ?? null,
        direccion: c.cliente?.direccion ?? null,
        ubigeo: c.cliente?.ubigeo ?? null,
        pais: "PE",
        email: c.cliente?.correo ?? null,
      },
      totales: {
        gravado: Number(c.subtotal_gravado ?? c.subtotal ?? 0),
        exonerado: Number(c.subtotal_exonerado ?? 0),
        inafecto: 0,
        descuentoGlobal: Number(c.descuento_global ?? 0),
        igv: Number(c.igv ?? 0),
        total,
      },
      referencia:
        c.tipo === "nota_credito" && c.documento_ref
          ? {
              tipoDocAfectado: c.documento_ref.tipo === "factura" ? "01" : "03",
              // El correlativo va con sus ceros: sin ellos SUNAT no encuentra
              // el comprobante que la nota dice corregir.
              numeroDocAfectado: `${c.documento_ref.serie}-${String(
                c.documento_ref.numero ?? "",
              ).padStart(8, "0")}`,
              codigoTipoNota: c.codigo_tipo_nota ?? "01",
              observaciones: c.motivo_nota || "Nota de crédito",
            }
          : null,
      items: items.map((it) => ({
        descripcion: it.descripcion,
        codigo: it.codigo ?? null,
        unidadMedida: it.unidad_medida ?? "NIU",
        cantidad: Number(it.cantidad ?? 1),
        precioUnitario: Number(it.precio_unitario ?? 0),
        tipoAfectacionIgv: it.tipo_afectacion_igv ?? "10",
        igvPorcentaje: Number(it.igv_porcentaje ?? 18),
        subtotal: Number(it.subtotal ?? 0),
        igv: Number(it.igv ?? 0),
        total: Number(it.total ?? 0),
      })),
      observaciones: c.observaciones ?? null,
    };
  }

  /**
   * Corta el envío de los comprobantes que la clínica sólo registra.
   *
   * Una empresa con emite_electronico = false numera, cobra y reporta aquí,
   * pero emite su talonario por fuera. Mandarla igual al PSE la emitiría con
   * las credenciales —y el RUC— de otra empresa del ERP.
   */
  private assertEmiteElectronico(c: any) {
    if (c?.emite_electronico === false) {
      throw new BadRequestException(
        `${c.numero_completo} es de una empresa que no emite electrónicamente desde el ERP: ` +
          "queda registrado acá y se emite por fuera. No se envía al PSE.",
      );
    }
  }

  private async datos(ctx: SpContext, comprobanteId: string) {
    const data = await this.sp.callCtx<any>("app.fn_comprobante_pse_datos", ctx, [comprobanteId]);
    const c = data?.comprobante;
    if (!c) throw new BadRequestException("Comprobante no encontrado");
    this.assertEmiteElectronico(c);
    return { data, c };
  }

  /** Envía —o reintenta— un comprobante a SUNAT a través del PSE. */
  async enviar(u: JwtPayload, comprobanteId: string) {
    const ctx = this.ctx(u);
    const { data, c } = await this.datos(ctx, comprobanteId);

    if (["aceptado_sunat", "anulado"].includes(c.estado)) {
      throw new BadRequestException(`El comprobante ya está en estado '${c.estado}'.`);
    }

    const { cred, emisor } = await this.credenciales(ctx, c.empresa_id);
    if (!emisor.ruc) {
      throw new BadRequestException(
        "La empresa no tiene RUC registrado: SUNAT no puede recibir un comprobante sin emisor.",
      );
    }

    const payload = this.construirPayload(data, emisor);
    const inicio = Date.now();

    try {
      const res = await this.adapter().enviarComprobante(payload, cred);

      // 1) queda registrado el documento en el proveedor
      await this.sp.callCtx("app.sp_comprobante_marcar_enviado", ctx, [
        comprobanteId,
        res.requestId,
        jsonbArg(payload as unknown as Record<string, unknown>),
      ]);

      // 2) se persiste lo que devolvió (estado, CDR, rutas)
      await this.sp.callCtx("app.sp_comprobante_recibir_respuesta", ctx, [
        comprobanteId,
        jsonbArg({
          estado: res.estadoFinal,
          response: res.raw ?? {},
          xml_url: res.xmlPath,
          pdf_url: res.pdfPath,
          cdr_url: res.cdrPath,
          sunat_codigo: res.codigoSunat,
          sunat_mensaje: res.mensajeSunat,
        }),
      ]);

      // 3) bitácora del intento
      await this.sp.callCtx("app.sp_comprobante_pse_log", ctx, [
        comprobanteId,
        jsonbArg({
          operacion: "enviar",
          request: payload,
          response: res.raw ?? {},
          exito: res.estadoFinal !== "rechazado_sunat",
          mensaje: res.mensajeSunat ?? "",
          duracion_ms: Date.now() - inicio,
        }),
      ]);

      return {
        estado: res.estadoFinal,
        aceptado: res.aceptado,
        mensaje: res.mensajeSunat ?? null,
        codigo_sunat: res.codigoSunat ?? null,
        request_id: res.requestId,
      };
    } catch (e: any) {
      // El intento fallido también se registra: sin eso, un rechazo del
      // proveedor no deja rastro en ningún lado.
      await this.sp
        .callCtx("app.sp_comprobante_pse_log", ctx, [
          comprobanteId,
          jsonbArg({
            operacion: "enviar",
            request: payload,
            response: { error: e?.message ?? String(e) },
            exito: false,
            mensaje: e?.message ?? "Error de envío",
            duracion_ms: Date.now() - inicio,
          }),
        ])
        .catch(() => undefined);
      throw e;
    }
  }

  /** Reconsulta el estado de un comprobante ya enviado. */
  async consultarEstado(u: JwtPayload, comprobanteId: string) {
    const ctx = this.ctx(u);
    const { c } = await this.datos(ctx, comprobanteId);

    if (!c.pse_request_id) {
      return { estado: c.estado, pendiente: true, mensaje: "Todavía no se envió al PSE." };
    }

    const { cred } = await this.credenciales(ctx, c.empresa_id);
    const res = await this.adapter().consultarEstado(c.pse_request_id, cred);

    await this.sp.callCtx("app.sp_comprobante_recibir_respuesta", ctx, [
      comprobanteId,
      jsonbArg({
        estado: res.estadoFinal,
        response: res.raw ?? {},
        sunat_codigo: res.codigoSunat,
        sunat_mensaje: res.mensajeSunat,
      }),
    ]);

    return {
      estado: res.estadoFinal,
      codigo_sunat: res.codigoSunat ?? null,
      mensaje: res.mensajeSunat ?? null,
    };
  }

  /**
   * Comunicación de baja. Es el camino de SUNAT para dar por no emitida una
   * factura dentro del plazo; para una boleta, o pasado el plazo, corresponde
   * la nota de crédito.
   */
  async comunicarBaja(u: JwtPayload, comprobanteId: string, motivo: string) {
    const ctx = this.ctx(u);
    const { c } = await this.datos(ctx, comprobanteId);

    if (!c.pse_request_id) {
      throw new BadRequestException(
        "El comprobante no se envió al PSE: no hay nada que dar de baja. Anúlalo en el ERP.",
      );
    }

    const { cred } = await this.credenciales(ctx, c.empresa_id);
    const adapter = this.adapter();
    if (!adapter.comunicarBaja) {
      throw new BadRequestException("El proveedor configurado no soporta la comunicación de baja.");
    }

    const inicio = Date.now();
    const res = await adapter.comunicarBaja(c.pse_request_id, motivo, cred);

    await this.sp.callCtx("app.sp_comprobante_pse_log", ctx, [
      comprobanteId,
      jsonbArg({
        operacion: "baja",
        request: { documento: c.pse_request_id, motivo },
        response: res.raw ?? {},
        exito: res.aceptado,
        mensaje: res.mensaje ?? "",
        duracion_ms: Date.now() - inicio,
      }),
    ]);

    if (res.aceptado) {
      await this.sp.callCtx("app.sp_comprobante_anular", ctx, [
        comprobanteId,
        `Comunicación de baja aceptada por SUNAT: ${motivo}`,
      ]);
    }

    return { aceptado: res.aceptado, codigo: res.codigo ?? null, mensaje: res.mensaje ?? null };
  }

  /**
   * Descarga el XML, el PDF o el CDR tal como quedaron en el proveedor. Es el
   * documento oficial: el que se le manda al propietario y el que vale ante
   * SUNAT, no una reimpresión del ERP.
   */
  async descargarArchivo(u: JwtPayload, comprobanteId: string, tipo: "XML" | "PDF" | "CDR") {
    const ctx = this.ctx(u);
    const { c } = await this.datos(ctx, comprobanteId);

    if (!c.pse_request_id) {
      throw new BadRequestException(
        "El comprobante todavía no se envió al PSE: no hay archivo que descargar.",
      );
    }
    if (this.modoSandbox) {
      throw new BadRequestException(
        "La descarga del comprobante oficial requiere el PSE real (PSE_MODE=real).",
      );
    }

    const { cred } = await this.credenciales(ctx, c.empresa_id);
    const adapter = this.adapter();
    if (!adapter.descargarArchivo) {
      throw new BadRequestException("El proveedor configurado no soporta la descarga de archivos.");
    }

    const res = await adapter.descargarArchivo(c.pse_request_id, tipo, cred);
    if (!res.contenidoBase64) {
      throw new BadRequestException(res.mensaje || `No se pudo obtener el ${tipo} del comprobante.`);
    }

    const ext = tipo === "PDF" ? "pdf" : "xml";
    return {
      tipo,
      nombre: `${c.numero_completo}${tipo === "CDR" ? " CDR" : ""}.${ext}`,
      mime: tipo === "PDF" ? "application/pdf" : "application/xml",
      contenido_base64: res.contenidoBase64,
    };
  }

  /** La cola de comprobantes que todavía no llegaron a SUNAT. */
  async porEnviar(u: JwtPayload) {
    return this.sp.callCtx<unknown[]>("app.fn_comprobantes_por_enviar", this.ctx(u), []);
  }

  /**
   * Envía en lote lo que quedó pendiente. Es lo que corre administración al
   * cierre del día. Un rechazo no corta el lote: cada comprobante deja su
   * resultado y se sigue con el siguiente.
   */
  async enviarPendientes(u: JwtPayload) {
    const pendientes = ((await this.porEnviar(u)) ?? []) as any[];
    const porEnviar = pendientes.filter((c) =>
      ["emitido", "pendiente_envio", "rechazado_sunat"].includes(c.estado),
    );

    const resultados = [];
    for (const c of porEnviar) {
      try {
        const r = await this.enviar(u, c.id);
        resultados.push({ id: c.id, numero: c.numero_completo, ...r });
      } catch (e: any) {
        this.logger.warn(`No se pudo enviar ${c.numero_completo}: ${e?.message}`);
        resultados.push({
          id: c.id,
          numero: c.numero_completo,
          estado: "error",
          mensaje: e?.message ?? "Error de envío",
        });
      }
    }

    const aceptados = resultados.filter((r) => (r as any).estado === "aceptado_sunat").length;
    return { total: resultados.length, aceptados, resultados };
  }
}

export type { EstadoPse };
