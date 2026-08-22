import { IsDateString, IsIn, IsOptional, IsString, IsUUID } from "class-validator";

export class SolicitarPermisoDto {
  @IsDateString() fecha_inicio!: string;
  @IsDateString() fecha_fin!: string;
  @IsOptional() @IsUUID() user_id?: string;
  @IsOptional() @IsIn(["personal", "vacaciones", "medico", "duelo", "capacitacion"]) tipo?: string;
  @IsOptional() @IsString() hora_inicio?: string;
  @IsOptional() @IsString() hora_fin?: string;
  @IsOptional() @IsString() motivo?: string;
}
