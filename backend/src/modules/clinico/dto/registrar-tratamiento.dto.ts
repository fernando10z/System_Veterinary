import { IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

const VIAS = ["oral","subcutanea","intramuscular","intravenosa","topica","oftalmica","otica","inhalatoria","rectal"];

export class RegistrarTratamientoDto {
  @IsUUID() mascota_id!: string;
  @IsString() @MaxLength(200) medicamento!: string;
  @IsString() @MaxLength(120) dosis!: string;
  @IsOptional() @IsUUID() consulta_id?: string;
  @IsOptional() @IsUUID() veterinario_id?: string;
  @IsOptional() @IsUUID() producto_id?: string;
  @IsOptional() @IsString() @MaxLength(200) principio_activo?: string;
  @IsOptional() @IsIn(VIAS) via?: string;
  @IsOptional() @IsInt() @Min(1) frecuencia_horas?: number;
  @IsOptional() @IsInt() @Min(1) duracion_dias?: number;
  @IsOptional() @IsDateString() fecha_inicio?: string;
  @IsOptional() @IsDateString() fecha_fin?: string;
  @IsOptional() @IsString() indicaciones?: string;
}
