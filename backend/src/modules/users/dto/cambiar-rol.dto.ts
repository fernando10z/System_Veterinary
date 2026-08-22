import { IsOptional, IsUUID } from "class-validator";

export class CambiarRolDto {
  @IsUUID() rolId!: string;
  /** Requerida cuando el rol tiene alcance de sede. */
  @IsOptional() @IsUUID() empresaId?: string;
}
