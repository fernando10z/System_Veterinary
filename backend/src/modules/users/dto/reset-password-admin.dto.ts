import { IsString, MinLength } from "class-validator";

export class ResetPasswordAdminDto {
  @IsString() @MinLength(8, { message: "La contraseña temporal debe tener al menos 8 caracteres" })
  password_temp!: string;
}
