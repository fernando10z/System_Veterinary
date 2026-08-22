import { IsString, MinLength } from "class-validator";

export class ActivarPortalDto {
  @IsString() @MinLength(8, { message: "La contraseña del portal debe tener al menos 8 caracteres" })
  password!: string;
}
