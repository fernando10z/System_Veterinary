import { IsDateString, IsObject, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class RegistrarExamenDto {
  @IsUUID() mascota_id!: string;
  @IsString() @MaxLength(60) tipo!: string;
  @IsString() @MaxLength(200) nombre!: string;
  @IsOptional() @IsUUID() consulta_id?: string;
  @IsOptional() @IsUUID() servicio_id?: string;
  @IsOptional() @IsUUID() veterinario_id?: string;
  @IsOptional() @IsDateString() fecha_solicitud?: string;
  @IsOptional() @IsDateString() fecha_resultado?: string;
  @IsOptional() @IsString() resultado?: string;
  /** Valores estructurados: {"hematocrito": 42, "referencia": "37-55"} */
  @IsOptional() @IsObject() valores?: Record<string, unknown>;
  @IsOptional() @IsString() interpretacion?: string;
  @IsOptional() @IsString() archivo_url?: string;
}
