import { IsIn, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class GuardarEspecializacionDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsString() @MaxLength(150) nombre?: string;
  @IsOptional() @IsString() @MaxLength(50) codigo?: string;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}
