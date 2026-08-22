import { IsBoolean, IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

export class GuardarProductoDto {
  @IsOptional() @IsUUID() id?: string;
  @IsOptional() @IsString() @MaxLength(200) nombre?: string;
  @IsOptional() @IsString() @MaxLength(40) codigo?: string;
  @IsOptional() @IsString() @MaxLength(60) codigo_barras?: string;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsIn(["medicamento", "insumo", "alimento", "accesorio", "vacuna", "otro"]) tipo?: string;
  @IsOptional() @IsUUID() categoria_id?: string;
  @IsOptional() @IsString() @MaxLength(200) principio_activo?: string;
  @IsOptional() @IsString() @MaxLength(120) laboratorio?: string;
  @IsOptional() @IsString() @MaxLength(120) presentacion?: string;
  @IsOptional() @IsString() @MaxLength(20) unidad_medida?: string;
  @IsOptional() @IsBoolean() requiere_receta?: boolean;
  @IsOptional() @IsBoolean() controlado?: boolean;
  @IsOptional() @IsBoolean() refrigerado?: boolean;
  @IsOptional() @IsNumber() @Min(0) precio_compra?: number;
  @IsOptional() @IsNumber() @Min(0) precio_venta?: number;
  @IsOptional() @IsBoolean() afecto_igv?: boolean;
  @IsOptional() @IsNumber() @Min(0) stock_minimo?: number;
  @IsOptional() @IsNumber() @Min(0) stock_maximo?: number;
  /** Solo al crear: entra como movimiento para que el kardex tenga origen. */
  @IsOptional() @IsNumber() @Min(0) stock_inicial?: number;
  @IsOptional() @IsBoolean() maneja_lotes?: boolean;
  @IsOptional() @IsIn(["activo", "inactivo"]) estado?: string;
}
