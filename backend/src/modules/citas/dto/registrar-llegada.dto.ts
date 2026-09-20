import { IsIn, IsInt, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

const PRIORIDADES = ["normal", "preferente", "urgencia", "emergencia"];

/**
 * El paciente llegó. Con `cita_id` se marca la llegada de una cita existente;
 * sin él —pero con `mascota_id`— se registra una atención sin cita previa.
 */
export class RegistrarLlegadaDto {
  @IsOptional() @IsUUID() cita_id?: string;
  @IsOptional() @IsUUID() mascota_id?: string;

  /** Triaje del mostrador. Sólo puede agravar la prioridad que traía la cita. */
  @IsOptional() @IsIn(PRIORIDADES) prioridad?: string;

  @IsOptional() @IsUUID() veterinario_id?: string;
  @IsOptional() @IsUUID() servicio_id?: string;
  @IsOptional() @IsUUID() consultorio_id?: string;
  @IsOptional() @IsInt() @Min(5) duracion_min?: number;
  @IsOptional() @IsString() @MaxLength(500) motivo?: string;
  @IsOptional() @IsString() @MaxLength(500) observaciones?: string;
}
