import { IsDateString, IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

/** Se suscribe la mascota, no el propietario: quien se vacuna es el animal. */
export class SuscribirDto {
  @IsUUID() plan_id!: string;
  @IsUUID() mascota_id!: string;
  @IsOptional() @IsDateString() fecha_inicio?: string;
  /** El precio se congela al contratar. */
  @IsOptional() @IsNumber() @Min(0) precio_pactado?: number;
  @IsOptional() @IsIn(["mensual", "trimestral", "semestral", "anual"]) periodicidad?: string;
  @IsOptional() @IsUUID() renovada_de?: string;
  @IsOptional() @IsString() @MaxLength(500) notas?: string;
}

export class CancelarSuscripcionDto {
  @IsOptional() @IsString() @MaxLength(500) motivo?: string;
}
