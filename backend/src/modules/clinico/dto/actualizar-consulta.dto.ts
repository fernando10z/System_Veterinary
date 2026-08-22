import {
  IsDateString, IsInt, IsNumber, IsOptional, IsString, Max, MaxLength, Min,
} from "class-validator";

export class ActualizarConsultaDto {
  @IsOptional() @IsString() motivo?: string;
  @IsOptional() @IsString() anamnesis?: string;
  @IsOptional() @IsNumber() @Min(0) @Max(200) peso_kg?: number;
  @IsOptional() @IsNumber() @Min(25) @Max(45) temperatura_c?: number;
  @IsOptional() @IsInt() @Min(0) @Max(400) frecuencia_cardiaca?: number;
  @IsOptional() @IsInt() @Min(0) @Max(200) frecuencia_respiratoria?: number;
  @IsOptional() @IsString() @MaxLength(60) mucosas?: string;
  @IsOptional() @IsNumber() @Min(0) @Max(10) tllc_seg?: number;
  @IsOptional() @IsInt() @Min(1) @Max(9) condicion_corporal?: number;
  @IsOptional() @IsString() examen_fisico?: string;
  @IsOptional() @IsString() diagnostico?: string;
  @IsOptional() @IsString() diagnostico_diferencial?: string;
  @IsOptional() @IsString() @MaxLength(60) pronostico?: string;
  @IsOptional() @IsString() plan_terapeutico?: string;
  @IsOptional() @IsString() prescripcion?: string;
  @IsOptional() @IsString() indicaciones_casa?: string;
  @IsOptional() @IsDateString() proxima_visita?: string;
}
