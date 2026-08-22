import { Type } from "class-transformer";
import { IsArray, IsBoolean, IsInt, IsOptional, IsString, Max, Min, ValidateNested } from "class-validator";

class HorarioDto {
  /** 0 = domingo … 6 = sábado */
  @IsInt() @Min(0) @Max(6) dia_semana!: number;
  @IsString() hora_inicio!: string;
  @IsString() hora_fin!: string;
  @IsOptional() @IsBoolean() activo?: boolean;
  @IsOptional() @IsBoolean() es_guardia?: boolean;
}

export class GuardarHorariosDto {
  /** Se reemplaza la semana completa: lo que no venga aquí se elimina. */
  @IsArray() @ValidateNested({ each: true }) @Type(() => HorarioDto)
  horarios!: HorarioDto[];
}
