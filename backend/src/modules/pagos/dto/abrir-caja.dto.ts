import { IsNumber, IsOptional, IsString, Min } from "class-validator";

export class AbrirCajaDto {
  @IsOptional() @IsNumber() @Min(0) monto_apertura?: number;
  @IsOptional() @IsString() observaciones?: string;
}
