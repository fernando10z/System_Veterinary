import { IsDateString, IsIn, IsOptional, IsString } from "class-validator";

export class AltaHospitalizacionDto {
  @IsOptional() @IsDateString() fecha_alta?: string;
  @IsOptional() @IsString() indicaciones_alta?: string;
  @IsOptional() @IsIn(["alta", "fallecido", "derivado"]) estado?: string;
}
