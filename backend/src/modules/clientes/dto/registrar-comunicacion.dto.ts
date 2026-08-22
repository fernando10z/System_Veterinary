import { IsBoolean, IsDateString, IsIn, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class RegistrarComunicacionDto {
  @IsUUID() cliente_id!: string;
  @IsOptional() @IsUUID() mascota_id?: string;
  @IsOptional() @IsIn(["llamada", "correo", "whatsapp", "sms", "presencial", "otro"]) tipo?: string;
  @IsOptional() @IsString() @MaxLength(255) asunto?: string;
  @IsString() mensaje!: string;
  @IsOptional() @IsBoolean() requiere_seguimiento?: boolean;
  @IsOptional() @IsDateString() fecha_seguimiento?: string;
}
