import { IsDateString, IsOptional, IsString, IsUUID } from "class-validator";

export class SolicitarCitaPortalDto {
  @IsUUID() mascota_id!: string;
  /** Sede donde se quiere atender. */
  @IsUUID() empresa_id!: string;
  @IsDateString() fecha_hora!: string;
  @IsOptional() @IsUUID() servicio_id?: string;
  @IsOptional() @IsString() motivo?: string;
}
