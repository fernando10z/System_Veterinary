import {
  IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, Length, Max, MaxLength, Min,
} from "class-validator";

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
  @IsOptional() @IsString() @MaxLength(10) serie_nota_credito_default?: string;

  // Datos fiscales del emisor. SUNAT los quiere como nodos propios y rechaza
  // el comprobante si pasan de 30 caracteres (error 113).
  @IsOptional() @IsString() @MaxLength(120) urbanizacion?: string;
  @IsOptional() @IsString() @MaxLength(30) distrito?: string;
  @IsOptional() @IsString() @MaxLength(30) provincia?: string;
  @IsOptional() @IsString() @MaxLength(30) departamento?: string;

  /** false = la empresa registra sus comprobantes aquí pero los emite por fuera. */
  @IsOptional() @IsBoolean() emite_electronico?: boolean;
  @IsOptional() @IsString() @MaxLength(40) pse_proveedor?: string;
  /** RUC con el que se emite; puede diferir del operativo en homologación. */
  @IsOptional() @IsString() @Length(11, 11, { message: "El RUC del PSE debe tener 11 dígitos" })
  pse_ruc?: string;
  @IsOptional() @IsString() pse_endpoint?: string;
  @IsOptional() @IsString() pse_usuario?: string;
  /**
   * Clave en claro del proveedor. El servicio la cifra antes de que llegue a la
   * base: nunca se guarda ni se devuelve en claro.
   */
  @IsOptional() @IsString() @MaxLength(255) pse_password?: string;

  @IsOptional() @IsIn(["activa", "suspendida", "cerrada"]) estado?: string;
}
