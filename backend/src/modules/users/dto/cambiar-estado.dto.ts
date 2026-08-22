import { IsIn } from "class-validator";

export class CambiarEstadoDto {
  @IsIn(["activo", "inactivo", "bloqueado", "solicitud"], {
    message: "Estado no válido",
  })
  estado!: string;
}
