import { IsIn, IsInt, IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class GuardarCategoriaDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsIn(["servicio", "producto", "proveedor"]) ambito?: string;
  @IsOptional() @IsString() @MaxLength(120) nombre?: string;
  @IsOptional() @IsString() @MaxLength(40) codigo?: string;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsUUID() padre_id?: string;
  @IsOptional() @IsInt() orden?: number;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}
