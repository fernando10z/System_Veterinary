import { IsString, MinLength } from "class-validator";

export class CambiarPasswordPortalDto {
  @IsString() passwordActual!: string;
  @IsString() @MinLength(8, { message: "La contraseña nueva debe tener al menos 8 caracteres" })
  passwordNuevo!: string;
}
