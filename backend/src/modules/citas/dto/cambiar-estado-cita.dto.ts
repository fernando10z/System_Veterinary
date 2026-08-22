import { IsIn, IsOptional, IsString } from "class-validator";

export class CambiarEstadoCitaDto {
  @IsIn(["programada", "confirmada", "en_espera", "en_atencion", "completada", "cancelada", "no_asistio"], {
    message: "Estado de cita no válido",
  })
  estado!: string;

  /** Obligatorio cuando el estado es 'cancelada' (lo valida el SP). */
  @IsOptional() @IsString() motivo?: string;
}
