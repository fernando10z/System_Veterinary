import { IsDateString, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

/** Anota a un paciente para avisarle si se libera un cupo. */
export class AnotarListaEsperaDto {
  @IsUUID() mascota_id!: string;
  /** Desde cuándo le sirve el cupo. */
  @IsDateString() desde!: string;
  @IsOptional() @IsDateString() hasta?: string;
  @IsOptional() @IsUUID() servicio_id?: string;
  /** Si quiere con un veterinario en particular. */
  @IsOptional() @IsUUID() veterinario_id?: string;
  @IsOptional() @IsString() @MaxLength(500) nota?: string;
}
