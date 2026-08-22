import { IsString, MinLength } from "class-validator";

export class PortalLoginDto {
  /** DNI del propietario o su correo: cualquiera de los dos sirve. */
  @IsString() @MinLength(6)
  documento!: string;

  @IsString() @MinLength(6)
  password!: string;
}
