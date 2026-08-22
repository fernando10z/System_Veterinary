import { IsEmail, IsIn, IsInt, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

export class GuardarProveedorDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsIn(["DNI", "CE", "RUC", "PASAPORTE"]) tipo_documento?: string;
  @IsOptional() @IsString() @MaxLength(20) numero_documento?: string;
  @IsOptional() @IsString() @MaxLength(255) razon_social?: string;
  @IsOptional() @IsString() @MaxLength(255) nombre_comercial?: string;
  @IsOptional() @IsUUID() categoria_id?: string;
  @IsOptional() @IsString() direccion?: string;
  @IsOptional() @IsString() @MaxLength(30) telefono?: string;
  @IsOptional() @IsEmail({}, { message: "Ingresa un correo válido" }) correo?: string;
  @IsOptional() @IsString() @MaxLength(200) web?: string;
  @IsOptional() @IsInt() @Min(0) dias_credito?: number;
  @IsOptional() @IsString() @MaxLength(60) cuenta_bancaria?: string;
  @IsOptional() @IsString() @MaxLength(80) banco?: string;
  @IsOptional() @IsString() observaciones?: string;
  @IsOptional() @IsIn(["activo", "inactivo", "bloqueado"]) estado?: string;
}
