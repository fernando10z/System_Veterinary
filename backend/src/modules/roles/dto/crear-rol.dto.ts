import { IsIn, IsOptional, IsString, MaxLength } from "class-validator";

export class CrearRolDto {
  @IsString() @MaxLength(50) codigo!: string;
  @IsString() @MaxLength(100) nombre!: string;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsIn(["global", "global_restricted", "empresa"]) scope?: string;
}
