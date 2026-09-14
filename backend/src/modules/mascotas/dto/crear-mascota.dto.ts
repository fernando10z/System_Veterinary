import {
  IsBoolean, IsDateString, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID,
  MaxLength, Min,
} from "class-validator";

export class CrearMascotaDto {
  @IsUUID() cliente_id!: string;
  @IsString() @MaxLength(100) nombre!: string;
  @IsUUID() especie_id!: string;
  @IsOptional() @IsUUID() raza_id?: string;
  @IsOptional() @IsIn(["macho", "hembra", "desconocido"]) sexo?: string;
  @IsOptional() @IsString() @MaxLength(80) color?: string;
  @IsOptional() @IsString() senias_particulares?: string;
  @IsOptional() @IsDateString() fecha_nacimiento?: string;
  @IsOptional() @IsInt() @Min(0) edad_aproximada_meses?: number;
  @IsOptional() @IsNumber() @Min(0) peso_kg?: number;
  @IsOptional() @IsIn(["toy", "pequenio", "mediano", "grande", "gigante"]) tamanio?: string;
  @IsOptional() @IsBoolean() esterilizado?: boolean;
  @IsOptional() @IsDateString() fecha_esterilizacion?: string;
  @IsOptional() @IsString() @MaxLength(40) microchip?: string;
  @IsOptional() @IsString() @MaxLength(40) num_placa?: string;
  @IsOptional() @IsString() foto_url?: string;
  @IsOptional() @IsString() alergias?: string;
  @IsOptional() @IsString() condiciones_cronicas?: string;
  @IsOptional() @IsString() observaciones?: string;
}
