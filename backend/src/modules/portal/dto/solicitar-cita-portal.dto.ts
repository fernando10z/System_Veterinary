import { IsDateString, IsOptional, IsString, IsUUID } from "class-validator";

export class SolicitarCitaPortalDto {
  @IsUUID() mascota_id!: string;
  @IsDateString() fecha_hora!: string;
  @IsOptional() @IsUUID() servicio_id?: string;
  @IsOptional() @IsString() motivo?: string;
  // La empresa NO se acepta del cliente: el SP la toma del propietario, para
  // que no pueda pedir cita en una empresa que no es la suya.
}
