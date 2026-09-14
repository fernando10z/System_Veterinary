import { IsString, MinLength } from "class-validator";

export class CambiarPasswordDto {
  @IsString() password_actual!: string;

  @IsString() @MinLength(8, { message: "La contraseña nueva debe tener al menos 8 caracteres" })
  password_nuevo!: string;
}
