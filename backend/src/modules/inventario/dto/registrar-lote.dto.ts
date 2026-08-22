import { IsDateString, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

export class RegistrarLoteDto {
  @IsUUID() producto_id!: string;
  @IsString() @MaxLength(60) numero_lote!: string;
  @IsNumber() @Min(0.01) cantidad!: number;
  @IsOptional() @IsDateString() fecha_vencimiento?: string;
  @IsOptional() @IsNumber() @Min(0) costo_unitario?: number;
  @IsOptional() @IsUUID() almacen_id?: string;
  @IsOptional() @IsUUID() proveedor_id?: string;
}
