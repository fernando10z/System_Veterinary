import { IsDateString, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from "class-validator";

export class RegistrarEvaluacionDto {
  @IsUUID() user_id!: string;
  @IsString() @MaxLength(20) periodo!: string;
  @IsOptional() @IsDateString() fecha?: string;
  @IsOptional() @IsInt() @Min(1) @Max(5) puntualidad?: number;
  @IsOptional() @IsInt() @Min(1) @Max(5) eficiencia?: number;
  @IsOptional() @IsInt() @Min(1) @Max(5) calidad_atencion?: number;
  @IsOptional() @IsInt() @Min(1) @Max(5) trabajo_equipo?: number;
  @IsOptional() @IsString() observaciones?: string;
}
