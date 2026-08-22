import { Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import * as nodemailer from "nodemailer";
import type { Transporter } from "nodemailer";

export interface MailAttachment {
  filename: string;
  content: string; // base64 (sin el prefijo data:)
  contentType?: string;
  /** Si se define, la imagen se incrusta en el HTML (referenciable como `cid:<cid>`) en vez de adjuntarse como descarga. */
  cid?: string;
}

export interface SendMailInput {
  to: string;
  subject: string;
  html: string;
  text?: string;
  attachments?: MailAttachment[];
}

/** Configuración SMTP por remitente (cada vendedor envía desde su cuenta). */
export interface SmtpConfig {
  host: string;
  port: number;
  secure: boolean;
  user: string;
  pass: string;
  from: string; // "Nombre <correo>" o solo el correo
}

@Injectable()
export class MailService {
  private readonly logger = new Logger(MailService.name);
  private globalTransporter: Transporter | null = null;

  constructor(private readonly config: ConfigService) {}

  /** Indica si hay configuración SMTP global (.env) suficiente. */
  isConfigured(): boolean {
    return !!this.config.get<string>("mail.host") && !!this.config.get<string>("mail.user");
  }

  private getGlobalTransporter(): Transporter {
    if (this.globalTransporter) return this.globalTransporter;
    this.globalTransporter = nodemailer.createTransport({
      host: this.config.get<string>("mail.host"),
      port: this.config.get<number>("mail.port"),
      secure: this.config.get<boolean>("mail.secure"),
      auth: {
        user: this.config.get<string>("mail.user"),
        pass: this.config.get<string>("mail.pass"),
      },
    });
    return this.globalTransporter;
  }

  /**
   * Envía un correo. Si se pasa `smtp`, usa esa cuenta (SMTP por usuario);
   * si no, cae al SMTP global del .env.
   */
  async send(input: SendMailInput, smtp?: SmtpConfig): Promise<void> {
    let transporter: Transporter;
    let from: string;

    if (smtp) {
      transporter = nodemailer.createTransport({
        host: smtp.host,
        port: smtp.port,
        secure: smtp.secure,
        auth: { user: smtp.user, pass: smtp.pass },
        // Si host/puerto están mal, fallar rápido en vez de colgarse hasta el timeout del SO
        connectionTimeout: 10_000,
        greetingTimeout: 10_000,
        socketTimeout: 20_000,
      });
      from = smtp.from;
    } else {
      if (!this.isConfigured()) {
        throw new Error(
          "El servicio de correo no está configurado. Define SMTP_HOST, SMTP_USER y SMTP_PASS en el .env del backend.",
        );
      }
      transporter = this.getGlobalTransporter();
      from = this.config.get<string>("mail.from") ?? "";
    }

    await transporter.sendMail({
      from,
      to: input.to,
      subject: input.subject,
      text: input.text,
      html: input.html,
      attachments: (input.attachments ?? []).map((a) => ({
        filename: a.filename,
        content: a.content,
        encoding: "base64",
        contentType: a.contentType ?? "application/pdf",
        ...(a.cid ? { cid: a.cid } : {}),
      })),
    });
    this.logger.log(`Correo enviado a ${input.to} · ${input.subject}`);
  }
}
