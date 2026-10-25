import { ValidateIf } from "class-validator";

/**
 * Como `@IsOptional()`, pero también deja pasar la cadena vacía.
 *
 * En una actualización, `""` significa "borra este dato" (el SP lo convierte en
 * NULL). Con `@IsOptional() @IsEmail()` el correo vacío se rechazaba, y no
 * había forma de quitarle el correo a un propietario ni la fecha de
 * nacimiento a un paciente.
 */
export function Vaciable(): PropertyDecorator {
  return ValidateIf((_o, v) => v !== undefined && v !== null && v !== "");
}
