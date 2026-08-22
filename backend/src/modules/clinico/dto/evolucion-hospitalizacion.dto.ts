import { IsBoolean, IsDateString, IsInt, IsNumber, IsOptional, IsString, IsUUID, Max, Min } from "class-validator";

export class EvolucionHospitalizacionDto {
  @IsUUID() hospitalizacion_id!: string;
  @IsOptional() @IsDateString() fecha_hora?: string;
  @IsOptional() @IsNumber() @Min(25) @Max(45) temperatura_c?: number;
  @IsOptional() @IsInt() @Min(0) @Max(400) frecuencia_cardiaca?: number;
  @IsOptional() @IsInt() @Min(0) @Max(200) frecuencia_respiratoria?: number;
  @IsOptional() @IsBoolean() come?: boolean;
  @IsOptional() @IsBoolean() orina?: boolean;
  @IsOptional() @IsBoolean() defeca?: boolean;
  @IsOptional() @IsString() nota?: string;
}
