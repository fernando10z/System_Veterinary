import { IsBoolean, IsIn, IsOptional, IsString, MaxLength } from "class-validator";

const CANALES = ["llamada", "correo", "whatsapp", "sms", "presencial", "otro"];

/**
 * Se contactó al propietario. El mensaje se guarda en la bitácora del cliente
 * tal como salió, no la plantilla: lo que importa es qué se le dijo.
 */
export class ContactarRecordatorioDto {
  @IsOptional() @IsIn(CANALES) canal?: string;
  @IsOptional() @IsString() @MaxLength(2000) mensaje?: string;
  /** El propietario ya respondió y agendó: el recordatorio se cierra. */
  @IsOptional() @IsBoolean() completar?: boolean;
}
