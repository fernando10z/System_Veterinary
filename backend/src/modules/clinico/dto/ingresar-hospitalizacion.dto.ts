import { IsDateString, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class IngresarHospitalizacionDto {
  @IsUUID() mascota_id!: string;
  @IsString() motivo!: string;
  @IsOptional() @IsUUID() veterinario_id?: string;
  @IsOptional() @IsUUID() consultorio_id?: string;
  @IsOptional() @IsString() @MaxLength(40) jaula?: string;
  @IsOptional() @IsString() diagnostico?: string;
  @IsOptional() @IsDateString() fecha_ingreso?: string;
}
