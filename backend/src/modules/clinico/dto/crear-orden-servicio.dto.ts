import { IsIn, IsNumber, IsOptional, IsString, IsUUID, Min } from "class-validator";

export class CrearOrdenServicioDto {
  @IsUUID() mascota_id!: string;
  @IsUUID() servicio_id!: string;
  @IsOptional() @IsUUID() veterinario_id?: string;
  @IsOptional() @IsUUID() cita_id?: string;
  @IsOptional() @IsUUID() consulta_id?: string;
  @IsOptional() @IsNumber() @Min(0.01) cantidad?: number;
  /** Si se omite, se toma el precio del catálogo. */
  @IsOptional() @IsNumber() @Min(0) precio_unitario?: number;
  @IsOptional() @IsNumber() @Min(0) descuento?: number;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsIn(["pendiente", "en_curso", "completado", "anulado"]) estado?: string;
}
