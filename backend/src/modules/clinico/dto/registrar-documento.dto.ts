import { IsInt, IsOptional, IsString, IsUUID, MaxLength, Min } from "class-validator";

export class RegistrarDocumentoDto {
  @IsUUID() mascota_id!: string;
  @IsString() @MaxLength(255) titulo!: string;
  /** Clave del objeto en MinIO (la devuelve POST /archivos/upload). */
  @IsString() storage_key!: string;
  @IsOptional() @IsUUID() consulta_id?: string;
  @IsOptional() @IsString() @MaxLength(60) tipo?: string;
  @IsOptional() @IsString() descripcion?: string;
  @IsOptional() @IsString() @MaxLength(120) mime_type?: string;
  @IsOptional() @IsInt() @Min(0) tamanio_bytes?: number;
}
