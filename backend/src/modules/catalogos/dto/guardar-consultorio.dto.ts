import { IsIn, IsInt, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

export class GuardarConsultorioDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsString() @MaxLength(80) nombre?: string;
  @IsOptional() @IsIn(["consulta", "quirofano", "hospitalizacion", "grooming"]) tipo?: string;
  @IsOptional() @IsInt() @Min(1) capacidad?: number;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}
