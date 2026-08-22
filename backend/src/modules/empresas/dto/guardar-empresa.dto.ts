import { IsIn, IsInt, IsNumber, IsOptional, IsString, Length, Max, MaxLength, Min } from "class-validator";

export class GuardarEmpresaDto {
  @IsOptional() @IsString() @Length(11, 11, { message: "El RUC debe tener 11 dígitos" }) ruc?: string;
  @IsOptional() @IsString() @MaxLength(255) razon_social?: string;
  @IsOptional() @IsString() @MaxLength(255) nombre_comercial?: string;
  @IsOptional() @IsString() direccion_fiscal?: string;
  @IsOptional() @IsString() @MaxLength(6) ubigeo?: string;
  @IsOptional() @IsString() @MaxLength(30) telefono?: string;
  @IsOptional() @IsString() @MaxLength(150) correo?: string;
  @IsOptional() @IsString() logo_url?: string;
  @IsOptional() @IsString() @MaxLength(10) serie_factura_default?: string;
  @IsOptional() @IsString() @MaxLength(10) serie_boleta_default?: string;
  @IsOptional() @IsString() @MaxLength(10) serie_nota_venta_default?: string;
  @IsOptional() @IsNumber() @Min(0) @Max(1) igv_tasa?: number;
  @IsOptional() @IsInt() @Min(1) aforo_consultorios?: number;
  @IsOptional() @IsInt() @Min(5) duracion_cita_min?: number;
  @IsOptional() @IsString() pse_endpoint?: string;
  @IsOptional() @IsString() pse_usuario?: string;
  @IsOptional() @IsIn(["activa", "suspendida", "cerrada"]) estado?: string;
}
