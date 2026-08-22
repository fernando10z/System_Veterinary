import { IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

export class GuardarEspecieDto {
  /** Presente = editar; ausente = crear. */
  @IsOptional() @IsUUID() id?: string;
  @IsString() @MaxLength(80) nombre!: string;
  @IsOptional() @IsString() @MaxLength(30) codigo?: string;
  @IsOptional() @IsString() @MaxLength(80) nombre_cria?: string;
  /** Nombre del icono lucide para la UI. */
  @IsOptional() @IsString() @MaxLength(40) icono?: string;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}

export class GuardarRazaDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsUUID() especie_id?: string;
  @IsOptional() @IsString() @MaxLength(120) nombre?: string;
  @IsOptional() @IsIn(["toy", "pequenio", "mediano", "grande", "gigante"]) tamanio_referencia?: string;
  @IsOptional() @IsNumber() @Min(0) peso_min_kg?: number;
  @IsOptional() @IsNumber() @Min(0) peso_max_kg?: number;
  @IsOptional() @IsInt() @Min(0) esperanza_vida?: number;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}
