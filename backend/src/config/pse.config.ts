import { registerAs } from "@nestjs/config";

/**
 * Proveedor de facturación electrónica (PSE/OSE). La clínica contrata
 * The Factory HKA: el ERP le manda el comprobante en JSON y ellos arman el XML
 * UBL 2.1, lo firman, lo envían a SUNAT y devuelven el CDR y el PDF.
 *
 * PSE_MODE elige el adaptador:
 *   - "sandbox" (por defecto): mock, simula la aceptación sin salir a la red.
 *     Permite ejercitar el flujo completo antes de tener credenciales.
 *   - "real": llama a la API de The Factory HKA con las credenciales de la
 *     empresa.
 *
 * Las credenciales viven por empresa en core.empresas (pse_endpoint,
 * pse_usuario, pse_password_enc): dos clínicas del mismo ERP emiten cada una
 * con su RUC. El endpoint de aquí es sólo el valor por defecto del ambiente.
 */
export default registerAs("pse", () => ({
  provider: process.env.PSE_PROVIDER ?? "the_factory_hka",
  mode: (process.env.PSE_MODE ?? "sandbox").toLowerCase(), // "sandbox" | "real"
  endpoint: process.env.PSE_ENDPOINT ?? "",
  timeoutMs: Number(process.env.PSE_TIMEOUT_MS ?? 15000),
}));
