import { IsString, MinLength } from "class-validator";

export class AnularComprobanteDto {
  @IsString() @MinLength(5, { message: "Indica el motivo de la anulación" })
  motivo!: string;
}
