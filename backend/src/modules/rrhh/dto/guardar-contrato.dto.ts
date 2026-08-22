import { IsBoolean, IsDateString, IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

export class GuardarContratoDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsUUID() user_id?: string;
  @IsOptional() @IsIn(["indefinido", "plazo_fijo", "locacion", "practicante", "freelance"]) tipo?: string;
  @IsOptional() @IsString() @MaxLength(120) cargo?: string;
  @IsOptional() @IsDateString() fecha_inicio?: string;
  @IsOptional() @IsDateString() fecha_fin?: string;
  @IsOptional() @IsNumber() @Min(0) salario?: number;
  @IsOptional() @IsIn(["PEN", "USD"]) moneda?: string;
  @IsOptional() @IsString() documento_url?: string;
  @IsOptional() @IsBoolean() vigente?: boolean;
}
