import { Type } from "class-transformer";
import { IsArray, IsNumber, IsOptional, IsUUID, Min, ValidateNested } from "class-validator";

class RecepcionItemDto {
  @IsUUID() item_id!: string;
  @IsNumber() @Min(0) cantidad!: number;
}

export class RecibirOrdenDto {
  /** Omitir para recibir todo lo pendiente de la orden. */
  @IsOptional() @IsArray() @ValidateNested({ each: true }) @Type(() => RecepcionItemDto)
  recepcion?: RecepcionItemDto[];
}
