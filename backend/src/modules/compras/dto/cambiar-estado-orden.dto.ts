import { IsIn } from "class-validator";

export class CambiarEstadoOrdenDto {
  @IsIn(["borrador", "enviada", "en_transito", "recibida_parcial", "recibida", "cancelada"])
  estado!: string;
}
