import { IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

const TIPOS = ["consulta","vacunacion","cirugia","laboratorio","imagen","grooming","hospitalizacion","desparasitacion","otro"];

export class GuardarServicioDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsString() @MaxLength(180) nombre?: string;
  @IsOptional() @IsString() @MaxLength(40) codigo?: string;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsIn(TIPOS) tipo?: string;
  @IsOptional() @IsUUID() categoria_id?: string;
  @IsOptional() @IsNumber() @Min(0) precio?: number;
  @IsOptional() @IsNumber() @Min(0) costo_estimado?: number;
  @IsOptional() @IsInt() @Min(0) duracion_min?: number;
  @IsOptional() @IsBoolean() requiere_ayuno?: boolean;
  @IsOptional() @IsBoolean() requiere_cita?: boolean;
  @IsOptional() @IsBoolean() afecto_igv?: boolean;
  @IsOptional() @IsUUID() producto_id?: string;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}
