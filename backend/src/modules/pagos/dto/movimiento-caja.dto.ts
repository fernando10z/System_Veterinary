import { IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

const METODOS = ["efectivo","tarjeta","transferencia","yape","plin","deposito","credito","mixto"];

export class MovimientoCajaDto {
  @IsIn(["ingreso", "egreso"]) tipo!: string;
  @IsString() @MaxLength(255) concepto!: string;
  @IsNumber() @Min(0.01) monto!: number;
  @IsOptional() @IsIn(METODOS) metodo?: string;
  @IsOptional() @IsUUID() caja_id?: string;
}
