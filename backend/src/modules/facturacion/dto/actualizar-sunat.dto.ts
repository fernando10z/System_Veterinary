import { IsIn, IsOptional, IsString, MaxLength } from "class-validator";

const ESTADOS = ["borrador","emitido","enviado_sunat","aceptado_sunat","rechazado_sunat","anulado"];

export class ActualizarSunatDto {
  @IsOptional() @IsIn(ESTADOS) estado?: string;
  @IsOptional() @IsString() @MaxLength(255) hash_cpe?: string;
  @IsOptional() @IsString() xml_url?: string;
  @IsOptional() @IsString() pdf_url?: string;
  @IsOptional() @IsString() cdr_url?: string;
  @IsOptional() @IsString() @MaxLength(20) sunat_codigo?: string;
  @IsOptional() @IsString() sunat_mensaje?: string;
}
