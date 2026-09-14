import { IsOptional, IsUUID } from "class-validator";

export class CambiarRolDto {
  @IsUUID() rol_id!: string;
  /** Requerida cuando el rol tiene alcance de empresa. */
  @IsOptional() @IsUUID() empresa_id?: string;
}
