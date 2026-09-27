import { Type } from "class-transformer";
import {
  IsArray, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID,
  Max, MaxLength, Min, ValidateNested,
} from "class-validator";

export class BeneficioPlanDto {
  @IsOptional() @IsIn(["servicio_incluido", "descuento_servicio", "descuento_producto"])
  tipo?: string;
  @IsOptional() @IsUUID() servicio_id?: string;
  @IsOptional() @IsUUID() categoria_id?: string;
  /** Cuántas veces entra en la vigencia. Vacío = sin tope. */
  @IsOptional() @IsInt() @Min(1) cantidad?: number;
  @IsOptional() @IsNumber() @Min(0) @Max(100) descuento_pct?: number;
  @IsOptional() @IsString() @MaxLength(255) descripcion?: string;
}

export class GuardarPlanDto {
  @IsOptional() @IsUUID() id?: string;
  @IsString() @MaxLength(180) nombre!: string;
  @IsOptional() @IsString() @MaxLength(40) codigo?: string;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsIn(["mensual", "trimestral", "semestral", "anual"]) periodicidad?: string;
  @IsOptional() @IsNumber() @Min(0) precio?: number;
  /** Cuánto dura la cobertura desde el alta. */
  @IsOptional() @IsInt() @Min(1) @Max(120) vigencia_meses?: number;
  @IsOptional() @IsUUID() especie_id?: string;
  @IsOptional() @IsInt() @Min(0) edad_min_meses?: number;
  @IsOptional() @IsInt() @Min(0) edad_max_meses?: number;
  /** Descuento sobre todo lo que no esté incluido explícitamente. */
  @IsOptional() @IsNumber() @Min(0) @Max(100) descuento_general_pct?: number;
  @IsOptional() @IsString() @MaxLength(20) color?: string;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;

  @IsOptional() @IsArray() @ValidateNested({ each: true }) @Type(() => BeneficioPlanDto)
  beneficios?: BeneficioPlanDto[];
}
