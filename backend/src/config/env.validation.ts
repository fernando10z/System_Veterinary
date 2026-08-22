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

  @IsString() REDIS_HOST!: string;
  @IsNumberString() REDIS_PORT!: string;
  @IsOptional() @IsString() REDIS_PASSWORD?: string;

  // SMTP opcional: sin él, el envío de recordatorios por correo queda apagado
  @IsOptional() @IsString() SMTP_HOST?: string;
  @IsOptional() @IsNumberString() SMTP_PORT?: string;
  @IsOptional() @IsBooleanString() SMTP_SECURE?: string;
  @IsOptional() @IsString() SMTP_USER?: string;
  @IsOptional() @IsString() SMTP_PASS?: string;
  @IsOptional() @IsString() MAIL_FROM?: string;
}

export function validateEnv(raw: Record<string, unknown>): EnvVars {
  const obj = plainToInstance(EnvVars, raw, { enableImplicitConversion: true });
  const errors = validateSync(obj, { skipMissingProperties: false, whitelist: false });
  if (errors.length) {
    const summary = errors
      .map((e) => `${e.property}: ${Object.values(e.constraints ?? {}).join(", ")}`)
      .join("\n  ");
    throw new Error(`Variables de entorno inválidas:\n  ${summary}`);
  }
  return obj;
}
