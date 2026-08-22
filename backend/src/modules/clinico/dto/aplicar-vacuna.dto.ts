import { IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

const VIAS = ["oral","subcutanea","intramuscular","intravenosa","topica","oftalmica","otica","inhalatoria","rectal"];

export class AplicarVacunaDto {
  @IsUUID() mascota_id!: string;
  @IsString() @MaxLength(150) nombre_vacuna!: string;
  @IsOptional() @IsUUID() veterinario_id?: string;
  @IsOptional() @IsUUID() consulta_id?: string;
  @IsOptional() @IsUUID() cita_id?: string;
  @IsOptional() @IsUUID() esquema_id?: string;
  /** Si se indica, la dosis se descuenta del inventario. */
  @IsOptional() @IsUUID() producto_id?: string;
  @IsOptional() @IsString() @MaxLength(120) laboratorio?: string;
  @IsOptional() @IsString() @MaxLength(60) lote?: string;
  @IsOptional() @IsDateString() fecha_aplicacion?: string;
  @IsOptional() @IsInt() @Min(1) dosis_numero?: number;
  @IsOptional() @IsDateString() proximo_refuerzo?: string;
  @IsOptional() @IsIn(VIAS) via?: string;
  @IsOptional() @IsString() reaccion_adversa?: string;
  @IsOptional() @IsString() observaciones?: string;
}
