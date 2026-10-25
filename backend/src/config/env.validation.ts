import { plainToInstance } from "class-transformer";
import {
  IsBooleanString, IsNumberString, IsOptional, IsString, MinLength, validateSync,
} from "class-validator";

/**
 * Validación de entorno al arrancar. Si falta algo crítico el proceso NO
 * levanta: es preferible fallar en el arranque que a mitad de una atención.
 */
class EnvVars {
  @IsOptional() @IsString() NODE_ENV?: string;
  @IsOptional() @IsNumberString() PORT?: string;

  @IsString() @MinLength(10) DATABASE_URL!: string;
  @IsOptional() @IsNumberString() DATABASE_POOL_MIN?: string;
  @IsOptional() @IsNumberString() DATABASE_POOL_MAX?: string;
  @IsOptional() @IsBooleanString() DATABASE_SSL?: string;

  @IsString() @MinLength(32) JWT_ACCESS_SECRET!: string;
  @IsString() @MinLength(32) JWT_REFRESH_SECRET!: string;
  @IsOptional() @IsString() JWT_ACCESS_EXPIRES?: string;
  @IsOptional() @IsString() JWT_REFRESH_EXPIRES?: string;
  @IsOptional() @IsString() JWT_ISSUER?: string;
  @IsOptional() @IsString() JWT_AUDIENCE?: string;

  // Portal del propietario: issuer/audience separados para aislarlo del backoffice
  @IsOptional() @IsString() JWT_PORTAL_ISSUER?: string;
  @IsOptional() @IsString() JWT_PORTAL_AUDIENCE?: string;

  @IsString() @MinLength(16) COOKIE_SECRET!: string;

  @IsString() STORAGE_ENDPOINT!: string;
  @IsString() STORAGE_ACCESS_KEY!: string;
  @IsString() STORAGE_SECRET_KEY!: string;
  @IsString() STORAGE_BUCKET!: string;
  // Dirección por la que el NAVEGADOR llega a MinIO (solo para firmar URLs).
  // En el despliegue con nginx: el propio dominio, p. ej. https://vet.clinica.pe
  @IsOptional() @IsString() STORAGE_PUBLIC_ENDPOINT?: string;

  @IsString() REDIS_HOST!: string;
  @IsNumberString() REDIS_PORT!: string;
  @IsOptional() @IsString() REDIS_PASSWORD?: string;

  @IsOptional() @IsBooleanString() COOKIE_SECURE?: string;
  @IsOptional() @IsString() TRUST_PROXY?: string;

  // Cifra la clave del PSE guardada por empresa. Sin ella no se puede emitir
  // electrónicamente, pero el resto del ERP funciona: por eso no es obligatoria.
  @IsOptional() @IsString() @MinLength(16) ENCRYPTION_KEY?: string;

  // Facturación electrónica. Sin configurar, el modo sandbox simula el envío.
  @IsOptional() @IsString() PSE_PROVIDER?: string;
  @IsOptional() @IsString() PSE_MODE?: string;
  @IsOptional() @IsString() PSE_ENDPOINT?: string;
  @IsOptional() @IsNumberString() PSE_TIMEOUT_MS?: string;

  // SMTP opcional: sin él, el envío de recordatorios por correo queda apagado
  @IsOptional() @IsString() SMTP_HOST?: string;
  @IsOptional() @IsNumberString() SMTP_PORT?: string;
  @IsOptional() @IsBooleanString() SMTP_SECURE?: string;
  @IsOptional() @IsString() SMTP_USER?: string;
  @IsOptional() @IsString() SMTP_PASS?: string;
  @IsOptional() @IsString() MAIL_FROM?: string;
}

/**
 * Reglas que solo aplican en producción. Conectarse como `postgres` funciona,
 * y por eso nadie lo nota: deja sin efecto toda la separación de 90_grants.sql
 * (el backend solo debe poder EXECUTE sobre app.*). En producción no se arranca
 * así salvo que se declare a propósito con ALLOW_DB_SUPERUSER=true.
 */
export function reglasProduccion(raw: Record<string, unknown>): string[] {
  if (raw.NODE_ENV !== "production") return [];
  const errores: string[] = [];
  try {
    const usuario = decodeURIComponent(new URL(String(raw.DATABASE_URL ?? "")).username);
    if (usuario === "postgres" && raw.ALLOW_DB_SUPERUSER !== "true") {
      errores.push(
        "DATABASE_URL: en producción el backend se conecta con vet_app_user, no con postgres",
      );
    }
  } catch {
    /* el formato ya lo valida MinLength; aquí solo interesa el usuario */
  }
  if (!raw.ENCRYPTION_KEY) {
    errores.push("ENCRYPTION_KEY: obligatoria en producción (cifra las credenciales del PSE)");
  }
  return errores;
}

export function validateEnv(raw: Record<string, unknown>): EnvVars {
  const obj = plainToInstance(EnvVars, raw, { enableImplicitConversion: true });
  const errors = validateSync(obj, { skipMissingProperties: false, whitelist: false });
  const lineas = [
    ...errors.map((e) => `${e.property}: ${Object.values(e.constraints ?? {}).join(", ")}`),
    ...reglasProduccion(raw),
  ];
  if (lineas.length) {
    throw new Error(`Variables de entorno inválidas:\n  ${lineas.join("\n  ")}`);
  }
  return obj;
}
