import { IsNumber, IsOptional, IsString, Min } from "class-validator";

export class CerrarCajaDto {
  /** Efectivo físico contado al cierre. */
  @IsNumber() @Min(0) monto_contado!: number;
  @IsOptional() @IsString() observaciones?: string;
}
