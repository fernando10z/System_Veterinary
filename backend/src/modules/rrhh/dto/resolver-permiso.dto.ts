import { IsIn, IsOptional, IsString } from "class-validator";

export class ResolverPermisoDto {
  @IsIn(["aprobado", "rechazado", "cancelado"]) estado!: string;
  @IsOptional() @IsString() comentario?: string;
}
