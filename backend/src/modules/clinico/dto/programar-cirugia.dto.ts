import { IsBoolean, IsDateString, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class ProgramarCirugiaDto {
  @IsUUID() mascota_id!: string;
  @IsString() @MaxLength(200) nombre!: string;
  @IsOptional() @IsUUID() cirujano_id?: string;
  @IsOptional() @IsUUID() anestesista_id?: string;
  @IsOptional() @IsUUID() consultorio_id?: string;
  @IsOptional() @IsUUID() servicio_id?: string;
  @IsOptional() @IsUUID() cita_id?: string;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsDateString() fecha_programada?: string;
  @IsOptional() @IsString() @MaxLength(120) anestesia_tipo?: string;
  @IsOptional() @IsBoolean() consentimiento_firmado?: boolean;
}
