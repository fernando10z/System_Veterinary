import { IsBoolean, IsEmail, IsIn, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class GuardarSedeDto {
  @IsOptional() @IsUUID() id?: string;
  @IsString() @MaxLength(120) nombre!: string;
  @IsOptional() @IsString() @MaxLength(30) codigo?: string;
  @IsOptional() @IsString() @MaxLength(255) direccion?: string;
  @IsOptional() @IsString() @MaxLength(80) distrito?: string;
  @IsOptional() @IsString() @MaxLength(80) provincia?: string;
  @IsOptional() @IsString() @MaxLength(80) departamento?: string;
  @IsOptional() @IsString() @MaxLength(10) ubigeo?: string;
  @IsOptional() @IsString() @MaxLength(30) telefono?: string;
  @IsOptional() @IsEmail({}, { message: "El correo de la sede no es válido" }) correo?: string;
  /** Serie propia del local: dos mostradores numerando la misma serie se pisan. */
  @IsOptional() @IsString() @MaxLength(10) serie_boleta?: string;
  @IsOptional() @IsString() @MaxLength(10) serie_factura?: string;
  @IsOptional() @IsBoolean() es_principal?: boolean;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}
