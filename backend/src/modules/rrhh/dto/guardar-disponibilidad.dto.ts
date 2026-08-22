import { IsDateString, IsIn, IsOptional, IsString, IsUUID } from "class-validator";

export class GuardarDisponibilidadDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsUUID() user_id?: string;
  @IsOptional() @IsDateString() fecha?: string;
  @IsOptional() @IsString() hora_inicio?: string;
  @IsOptional() @IsString() hora_fin?: string;
  @IsOptional() @IsIn(["laboral", "guardia", "libre", "vacaciones", "permiso", "capacitacion"]) tipo?: string;
  @IsOptional() @IsUUID() consultorio_id?: string;
  @IsOptional() @IsString() nota?: string;
}
