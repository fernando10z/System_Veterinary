import { IsBoolean, IsOptional, IsString, MaxLength } from "class-validator";

export class TerminarPeluqueriaDto {
  @IsOptional() @IsString() foto_salida?: string;
  @IsOptional() @IsString() @MaxLength(1000) observaciones_salida?: string;
}

export class EntregarPeluqueriaDto {
  @IsOptional() @IsString() @MaxLength(160) entregado_a?: string;
  @IsOptional() @IsString() @MaxLength(20) documento_receptor?: string;
  @IsOptional() @IsString() @MaxLength(1000) observaciones_salida?: string;
  /** Entregar aunque queden hallazgos urgentes sin revisar. Queda registrado. */
  @IsOptional() @IsBoolean() omitir_aviso?: boolean;
}

export class CancelarPeluqueriaDto {
  @IsOptional() @IsString() @MaxLength(500) motivo?: string;
}
