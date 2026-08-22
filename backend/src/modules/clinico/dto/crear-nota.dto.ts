import { IsBoolean, IsOptional, IsString, IsUUID } from "class-validator";

export class CrearNotaDto {
  @IsUUID() mascota_id!: string;
  @IsString() nota!: string;
  @IsOptional() @IsBoolean() destacada?: boolean;
}
