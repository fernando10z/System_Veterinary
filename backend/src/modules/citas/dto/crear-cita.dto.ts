import { IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Min } from "class-validator";

export class CrearCitaDto {
  @IsUUID() mascota_id!: string;
  @IsDateString() fecha_hora!: string;
  @IsOptional() @IsUUID() veterinario_id?: string;
  @IsOptional() @IsUUID() servicio_id?: string;
  @IsOptional() @IsUUID() consultorio_id?: string;
  @IsOptional() @IsInt() @Min(5) duracion_min?: number;
  @IsOptional() @IsString() motivo?: string;
  @IsOptional() @IsIn(["normal", "preferente", "urgencia", "emergencia"]) prioridad?: string;
  @IsOptional() @IsIn(["mostrador", "telefono", "whatsapp", "portal", "recurrente"]) origen?: string;
  @IsOptional() @IsIn(["programada", "confirmada"]) estado?: string;
  @IsOptional() @IsString() observaciones?: string;
}
