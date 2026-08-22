import { IsIn, IsInt, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class GuardarClausulaDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsIn(["consentimiento", "politica", "contrato"]) tipo?: string;
  @IsOptional() @IsString() @MaxLength(255) titulo?: string;
  @IsOptional() @IsString() contenido?: string;
  @IsOptional() @IsInt() orden?: number;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}
