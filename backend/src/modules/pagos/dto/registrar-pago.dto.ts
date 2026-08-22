import { Type } from "class-transformer";
import {
  IsArray, IsDateString, IsIn, IsNumber, IsOptional, IsString, IsUUID,
  MaxLength, Min, ValidateNested,
} from "class-validator";

const METODOS = ["efectivo","tarjeta","transferencia","yape","plin","deposito","credito","mixto"];

class AplicacionDto {
  @IsUUID() comprobante_id!: string;
  @IsNumber() @Min(0.01) monto!: number;
}

export class RegistrarPagoDto {
  @IsUUID() cliente_id!: string;
  @IsNumber() @Min(0.01, { message: "El monto debe ser mayor a cero" }) monto!: number;
  @IsOptional() @IsIn(METODOS) metodo?: string;
  @IsOptional() @IsIn(["PEN", "USD"]) moneda?: string;
  @IsOptional() @IsString() @MaxLength(120) referencia?: string;
  @IsOptional() @IsUUID() caja_id?: string;
  @IsOptional() @IsDateString() fecha_pago?: string;
  @IsOptional() @IsString() observaciones?: string;
  /** Omitir para imputar a los comprobantes más antiguos. */
  @IsOptional() @IsArray() @ValidateNested({ each: true }) @Type(() => AplicacionDto)
  aplicaciones?: AplicacionDto[];
}
