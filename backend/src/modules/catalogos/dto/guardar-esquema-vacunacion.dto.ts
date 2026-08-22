import { IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

export class GuardarEsquemaVacunacionDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsUUID() especie_id?: string;
  @IsOptional() @IsString() @MaxLength(150) nombre?: string;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsBoolean() obligatoria?: boolean;
  @IsOptional() @IsInt() @Min(0) edad_inicio_semanas?: number;
  @IsOptional() @IsInt() @Min(0) intervalo_dias?: number;
  @IsOptional() @IsInt() @Min(1) dosis_totales?: number;
  @IsOptional() @IsInt() @Min(0) revacunacion_meses?: number;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}
