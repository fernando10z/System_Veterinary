import { IsString, MinLength } from "class-validator";

export class CambiarPasswordDto {
  @IsString() passwordActual!: string;

  @IsString() @MinLength(8, { message: "La contraseña nueva debe tener al menos 8 caracteres" })
  passwordNuevo!: string;
}
