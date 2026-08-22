import { IsDateString, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

export class ReportarExtravioDto {
  @IsUUID() mascota_id!: string;
  @IsDateString() fecha_extravio!: string;
  @IsOptional() @IsString() @MaxLength(255) zona?: string;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsString() @MaxLength(150) contacto?: string;
  @IsOptional() @IsNumber() @Min(0) recompensa?: number;
}
