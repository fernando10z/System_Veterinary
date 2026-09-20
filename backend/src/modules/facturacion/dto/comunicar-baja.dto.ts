import { IsString, MaxLength, MinLength } from "class-validator";

export class ComunicarBajaDto {
  /** SUNAT exige el sustento de la baja; queda en el documento y en la auditoría. */
  @IsString()
  @MinLength(5, { message: "Indica el motivo de la baja" })
  @MaxLength(500)
  motivo!: string;
}
