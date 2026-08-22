import { IsDateString, IsIn, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class RegistrarDesparasitacionDto {
  @IsUUID() mascota_id!: string;
  @IsString() @MaxLength(150) producto_nombre!: string;
  @IsOptional() @IsUUID() veterinario_id?: string;
  @IsOptional() @IsUUID() consulta_id?: string;
  @IsOptional() @IsUUID() producto_id?: string;
  @IsOptional() @IsIn(["interna", "externa", "mixta"]) tipo?: string;
  @IsOptional() @IsString() @MaxLength(80) dosis?: string;
  @IsOptional() @IsDateString() fecha_aplicacion?: string;
  @IsOptional() @IsDateString() proxima_dosis?: string;
  @IsOptional() @IsString() observaciones?: string;
}
