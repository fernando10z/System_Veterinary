import { IsDateString, IsIn, IsOptional, IsString, IsUUID } from "class-validator";

export class AltaHospitalizacionDto {
  /**
   * Tarifa del día de internamiento. Si se indica, el alta deja el cargo por
   * los días que estuvo hospitalizado el paciente.
   */
  @IsOptional() @IsUUID() servicio_id?: string;
  @IsOptional() @IsDateString() fecha_alta?: string;
  @IsOptional() @IsString() indicaciones_alta?: string;
  @IsOptional() @IsIn(["alta", "fallecido", "derivado"]) estado?: string;
}
