import { IsIn, IsNumber, IsOptional, IsString, IsUUID, Min } from "class-validator";

const TIPOS = ["entrada","salida","ajuste_positivo","ajuste_negativo","transferencia","merma","vencimiento"];
const MOTIVOS = ["compra","venta","uso_clinico","donacion","ajuste_inventario","devolucion","vencido","traslado"];

export class MovimientoInventarioDto {
  @IsUUID() producto_id!: string;
  @IsIn(TIPOS) tipo!: string;
  @IsIn(MOTIVOS) motivo!: string;
  @IsNumber() @Min(0.01, { message: "La cantidad debe ser mayor a cero" }) cantidad!: number;
  @IsOptional() @IsUUID() almacen_id?: string;
  @IsOptional() @IsUUID() almacen_destino_id?: string;
  @IsOptional() @IsUUID() lote_id?: string;
  @IsOptional() @IsNumber() @Min(0) costo_unitario?: number;
  @IsOptional() @IsUUID() proveedor_id?: string;
  @IsOptional() @IsUUID() cliente_id?: string;
  @IsOptional() @IsUUID() mascota_id?: string;
  @IsOptional() @IsString() observaciones?: string;
}
