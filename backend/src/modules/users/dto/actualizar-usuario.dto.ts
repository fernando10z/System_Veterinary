import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class ActualizarUsuarioDto {
  @IsOptional() @IsString() @MaxLength(150) nombres?: string;
  @IsOptional() @IsString() @MaxLength(100) apellido_paterno?: string;
  @IsOptional() @IsString() @MaxLength(100) apellido_materno?: string;
  @IsOptional() @IsString() @MaxLength(30) telefono?: string;
  @IsOptional() @IsString() foto_url?: string;
  @IsOptional() @IsIn(["DNI", "CE", "RUC", "PASAPORTE"]) tipo_documento?: string;
  @IsOptional() @IsString() @MaxLength(20) numero_documento?: string;
  @IsOptional() @IsBoolean() es_veterinario?: boolean;
  @IsOptional() @IsString() @MaxLength(30) colegiatura?: string;
  @IsOptional() @IsUUID() especializacion_id?: string;
  @IsOptional() @IsString() @MaxLength(7) color_agenda?: string;
}
