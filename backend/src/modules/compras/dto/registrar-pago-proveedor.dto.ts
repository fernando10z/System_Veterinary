import { IsDateString, IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

const METODOS = ["efectivo","tarjeta","transferencia","yape","plin","deposito","credito","mixto"];

export class RegistrarPagoProveedorDto {
  @IsUUID() proveedor_id!: string;
  @IsNumber() @Min(0.01, { message: "El monto debe ser mayor a cero" }) monto!: number;
  @IsOptional() @IsUUID() orden_compra_id?: string;
  @IsOptional() @IsIn(METODOS) metodo?: string;
  @IsOptional() @IsIn(["PEN", "USD"]) moneda?: string;
  @IsOptional() @IsString() @MaxLength(120) referencia?: string;
  @IsOptional() @IsString() comprobante_url?: string;
  @IsOptional() @IsDateString() fecha_pago?: string;
  @IsOptional() @IsString() observaciones?: string;
}
