import { IsEmail, IsString, MinLength } from "class-validator";

export class SolicitarResetDto {
  @IsEmail({}, { message: "Ingresa un correo válido" })
  email!: string;
}

export class ResetPasswordDto {
  @IsString() token!: string;

  @IsString() @MinLength(8, { message: "La contraseña debe tener al menos 8 caracteres" })
  passwordNuevo!: string;
}
