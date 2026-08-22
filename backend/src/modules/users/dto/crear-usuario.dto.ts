import {
  IsBoolean, IsEmail, IsIn, IsOptional, IsString, IsUUID, MaxLength, MinLength,
} from "class-validator";

export class CrearUsuarioDto {
  @IsEmail({}, { message: "Ingresa un correo válido" }) email!: string;
  @IsString() @MinLength(8, { message: "La contraseña debe tener al menos 8 caracteres" }) password!: string;
  @IsString() @MaxLength(150) nombres!: string;
  @IsString() @MaxLength(100) apellido_paterno!: string;
  @IsOptional() @IsString() @MaxLength(100) apellido_materno?: string;
  @IsOptional() @IsIn(["DNI", "CE", "RUC", "PASAPORTE"]) tipo_documento?: string;
  @IsString() @MaxLength(20) numero_documento!: string;
  @IsOptional() @IsString() @MaxLength(30) telefono?: string;
  @IsOptional() @IsString() foto_url?: string;
  @IsOptional() @IsUUID() empresa_id?: string;
  @IsOptional() @IsUUID() rol_id?: string;
  @IsOptional() @IsBoolean() es_veterinario?: boolean;
  @IsOptional() @IsString() @MaxLength(30) colegiatura?: string;
  @IsOptional() @IsUUID() especializacion_id?: string;
  @IsOptional() @IsString() @MaxLength(7) color_agenda?: string;
  @IsOptional() @IsIn(["activo", "inactivo", "bloqueado", "solicitud"]) estado?: string;
  @IsOptional() @IsBoolean() must_change_password?: boolean;
}
