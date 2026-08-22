import { IsDateString, IsOptional, IsString, IsUUID } from "class-validator";

export class ReprogramarCitaDto {
  @IsDateString() fecha_hora!: string;
  @IsOptional() @IsString() motivo?: string;
  @IsOptional() @IsUUID() veterinario_id?: string;
}
