import { IsBoolean, IsDateString, IsIn, IsOptional, IsString, MaxLength } from "class-validator";

export class ResultadoCirugiaDto {
  @IsOptional() @IsDateString() fecha_inicio?: string;
  @IsOptional() @IsDateString() fecha_fin?: string;
  @IsOptional() @IsString() @MaxLength(120) anestesia_tipo?: string;
  @IsOptional() @IsString() @MaxLength(120) anestesia_dosis?: string;
  @IsOptional() @IsString() hallazgos?: string;
  @IsOptional() @IsString() complicaciones?: string;
  @IsOptional() @IsString() resultado?: string;
  @IsOptional() @IsString() cuidados_post?: string;
  /** Sin consentimiento firmado el SP no deja cerrar la cirugía. */
  @IsOptional() @IsBoolean() consentimiento_firmado?: boolean;
  @IsOptional() @IsIn(["programada", "en_quirofano", "realizada", "cancelada"]) estado?: string;
}
