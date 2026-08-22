import {
  IsBoolean, IsDateString, IsEmail, IsIn, IsInt, IsNumber, IsOptional, IsString,
  MaxLength, Min,
} from "class-validator";

export class CrearClienteDto {
  @IsOptional() @IsIn(["DNI", "CE", "RUC", "PASAPORTE"]) tipo_documento?: string;
  @IsString() @MaxLength(20) numero_documento!: string;
  @IsString() @MaxLength(150) nombres!: string;
  @IsOptional() @IsString() @MaxLength(100) apellido_paterno?: string;
  @IsOptional() @IsString() @MaxLength(100) apellido_materno?: string;
  @IsOptional() @IsString() @MaxLength(255) razon_social?: string;
  @IsOptional() @IsString() @MaxLength(30) telefono?: string;
  @IsOptional() @IsString() @MaxLength(30) telefono_alterno?: string;
  @IsOptional() @IsEmail({}, { message: "Ingresa un correo válido" }) correo?: string;
  @IsOptional() @IsString() direccion?: string;
  @IsOptional() @IsString() @MaxLength(6) ubigeo?: string;
  @IsOptional() @IsDateString() fecha_nacimiento?: string;
  @IsOptional() @IsNumber() @Min(0) linea_credito?: number;
  @IsOptional() @IsInt() @Min(0) dias_credito?: number;
  @IsOptional() @IsBoolean() acepta_marketing?: boolean;
  @IsOptional() @IsString() observaciones?: string;
}
