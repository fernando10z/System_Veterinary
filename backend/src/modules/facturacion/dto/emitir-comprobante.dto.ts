import { Type } from "class-transformer";
import {
  IsArray, IsBoolean, IsDateString, IsIn, IsNumber, IsOptional, IsString,
  IsUUID, MaxLength, Min, ValidateNested,
} from "class-validator";

class ItemComprobanteDto {
  @IsOptional() @IsIn(["servicio", "producto", "otro"]) tipo_item?: string;
  @IsString() @MaxLength(500) descripcion!: string;
  @IsNumber() @Min(0.01) cantidad!: number;
  @IsNumber() @Min(0) precio_unitario!: number;
  @IsOptional() @IsNumber() @Min(0) descuento?: number;
  @IsOptional() @IsBoolean() afecto_igv?: boolean;
  @IsOptional() @IsString() @MaxLength(40) codigo?: string;
  @IsOptional() @IsUUID() servicio_id?: string;
  @IsOptional() @IsUUID() producto_id?: string;
  @IsOptional() @IsUUID() orden_servicio_id?: string;
  @IsOptional() @IsUUID() insumo_id?: string;
}

export class EmitirComprobanteDto {
  @IsUUID() cliente_id!: string;
  @IsOptional() @IsIn(["factura", "boleta", "nota_venta"]) tipo?: string;
  /** Omitir para facturar todo lo pendiente del cliente. */
  @IsOptional() @IsArray() @ValidateNested({ each: true }) @Type(() => ItemComprobanteDto)
  items?: ItemComprobanteDto[];
  @IsOptional() @IsUUID() mascota_id?: string;
  @IsOptional() @IsUUID() cita_id?: string;
  @IsOptional() @IsUUID() consulta_id?: string;
  @IsOptional() @IsUUID() caja_id?: string;
  @IsOptional() @IsString() @MaxLength(10) serie?: string;
  @IsOptional() @IsDateString() fecha_emision?: string;
  @IsOptional() @IsDateString() fecha_vencimiento?: string;
  @IsOptional() @IsIn(["PEN", "USD"]) moneda?: string;
  @IsOptional() @IsNumber() @Min(0) descuento_global?: number;
  @IsOptional() @IsString() observaciones?: string;
}
