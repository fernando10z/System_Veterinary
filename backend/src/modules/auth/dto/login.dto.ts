import { IsEmail, IsString, MinLength } from "class-validator";

export class LoginDto {
  @IsEmail({}, { message: "Ingresa un correo válido" })
  email!: string;

  @IsString() @MinLength(6, { message: "La contraseña es demasiado corta" })
  password!: string;
}
