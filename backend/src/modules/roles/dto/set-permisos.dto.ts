import { IsArray, IsString } from "class-validator";

export class SetPermisosDto {
  /** Set completo: lo que no venga aquí se revoca. */
  @IsArray() @IsString({ each: true })
  codigos!: string[];
}
