import { IsBoolean, IsEmail, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class GuardarContactoDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsUUID() proveedor_id?: string;
  @IsOptional() @IsString() @MaxLength(150) nombres?: string;
  @IsOptional() @IsString() @MaxLength(100) cargo?: string;
  @IsOptional() @IsString() @MaxLength(30) telefono?: string;
  @IsOptional() @IsEmail() correo?: string;
  @IsOptional() @IsBoolean() es_principal?: boolean;
}
