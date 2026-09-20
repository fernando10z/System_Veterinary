import { Type } from "class-transformer";
import {
  IsArray, IsBoolean, IsNumber, IsOptional, IsString, IsUUID,
  MaxLength, MinLength, Min, ValidateNested,
} from "class-validator";

class ItemNotaCreditoDto {
  @IsUUID() comprobante_item_id!: string;
  /** Omitir para acreditar el ítem completo. */
  @IsOptional() @IsNumber() @Min(0.01) cantidad?: number;
}

export class EmitirNotaCreditoDto {
  @IsUUID() comprobante_id!: string;

  @IsString() @MinLength(5, { message: "Indica el motivo de la nota de crédito" })
  @MaxLength(500)
  motivo!: string;

  /** Omitir para acreditar el comprobante entero. */
  @IsOptional() @IsArray() @ValidateNested({ each: true }) @Type(() => ItemNotaCreditoDto)
  items?: ItemNotaCreditoDto[];

  @IsOptional() @IsString() @MaxLength(10) serie?: string;

  /** Una devolución de producto vuelve al almacén; una corrección de datos, no. */
  @IsOptional() @IsBoolean() repone_stock?: boolean;

  /** El servicio acreditado vuelve a quedar pendiente de cobro. */
  @IsOptional() @IsBoolean() devolver_a_pendientes?: boolean;

  @IsOptional() @IsString() @MaxLength(500) observaciones?: string;
}
