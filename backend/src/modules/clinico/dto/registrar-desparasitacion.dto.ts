import {
  IsDateString, IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min,
} from "class-validator";

export class RegistrarDesparasitacionDto {
  @IsUUID() mascota_id!: string;
  @IsString() @MaxLength(150) producto_nombre!: string;
  @IsOptional() @IsUUID() veterinario_id?: string;
  @IsOptional() @IsUUID() consulta_id?: string;
  /** Si se indica, el antiparasitario se descuenta del inventario y se cobra. */
  @IsOptional() @IsUUID() producto_id?: string;
  @IsOptional() @IsNumber() @Min(0.01) cantidad?: number;
  /** Tarifa del acto: si se indica, queda pendiente de cobro. */
  @IsOptional() @IsUUID() servicio_id?: string;
  @IsOptional() @IsIn(["interna", "externa", "mixta"]) tipo?: string;
  @IsOptional() @IsString() @MaxLength(80) dosis?: string;
  @IsOptional() @IsDateString() fecha_aplicacion?: string;
  @IsOptional() @IsDateString() proxima_dosis?: string;
  @IsOptional() @IsString() observaciones?: string;
}
