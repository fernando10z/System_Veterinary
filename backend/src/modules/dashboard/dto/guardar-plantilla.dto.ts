import { IsIn, IsOptional, IsString, MaxLength, MinLength } from "class-validator";

const TIPOS = ["vacuna", "desparasitacion", "control", "cita", "cumpleanios", "deuda"];

export class GuardarPlantillaDto {
  @IsIn(TIPOS) tipo!: string;
  /**
   * Admite {{propietario}}, {{paciente}}, {{clinica}}, {{fecha}}, {{titulo}}
   * y {{telefono_clinica}}. Lo que no se reconozca se borra al enviar.
   */
  @IsString() @MinLength(10) @MaxLength(2000) texto!: string;
  @IsOptional() @IsString() @MaxLength(120) nombre?: string;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}
