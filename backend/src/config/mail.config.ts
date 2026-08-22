import { registerAs } from "@nestjs/config";

export default registerAs("mail", () => ({
  host: process.env.SMTP_HOST ?? "",
  port: Number(process.env.SMTP_PORT ?? 587),
  // true => conexión TLS implícita (puerto 465); false => STARTTLS (587)
  secure: (process.env.SMTP_SECURE ?? "false") === "true",
  user: process.env.SMTP_USER ?? "",
  pass: process.env.SMTP_PASS ?? "",
  // Remitente por defecto: "Nombre <correo>". Si falta, se usa SMTP_USER.
  from: process.env.MAIL_FROM ?? process.env.SMTP_USER ?? "",
}));
