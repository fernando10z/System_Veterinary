import { Type } from "class-transformer";
import {
  ArrayMinSize, IsArray, IsDateString, IsIn, IsNumber, IsOptional, IsString,
  IsUUID, MaxLength, Min, ValidateNested,
} from "class-validator";

class ItemOrdenDto {
  @IsUUID() producto_id!: string;
  @IsNumber() @Min(0.01) cantidad!: number;
  @IsNumber() @Min(0) precio_unitario!: number;
  @IsOptional() @IsNumber() @Min(0) descuento?: number;
  @IsOptional() @IsString() @MaxLength(255) descripcion?: string;
  @IsOptional() @IsString() @MaxLength(60) numero_lote?: string;
  @IsOptional() @IsDateString() fecha_vencimiento?: string;
}

export class CrearOrdenCompraDto {
  @IsUUID() proveedor_id!: string;
  @IsArray() @ArrayMinSize(1, { message: "La orden necesita al menos un ítem" })
  @ValidateNested({ each: true }) @Type(() => ItemOrdenDto)
  items!: ItemOrdenDto[];
  @IsOptional() @IsUUID() almacen_id?: string;
  @IsOptional() @IsDateString() fecha_emision?: string;
  @IsOptional() @IsDateString() fecha_estimada?: string;
  @IsOptional() @IsIn(["PEN", "USD"]) moneda?: string;
  @IsOptional() @IsIn(["borrador", "enviada"]) estado?: string;
  @IsOptional() @IsString() observaciones?: string;
}
