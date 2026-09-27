import { Type } from "class-transformer";
import {
  ArrayMinSize, IsArray, IsBoolean, IsDateString, IsNumber, IsOptional,
  IsString, IsUUID, MaxLength, Min, ValidateNested,
} from "class-validator";

export class ServicioPeluqueriaDto {
  @IsUUID() servicio_id!: string;
  @IsOptional() @IsNumber() @Min(0.01) cantidad?: number;
  /** Si el mostrador pacta otro precio, manda el pactado. */
  @IsOptional() @IsNumber() @Min(0) precio_unitario?: number;
  @IsOptional() @IsString() @MaxLength(255) nota?: string;
}

/** Recepción del animal: qué se le va a hacer y en qué estado llegó. */
export class RecibirPeluqueriaDto {
  @IsUUID() mascota_id!: string;
  @IsArray() @ArrayMinSize(1, { message: "Indica al menos un servicio de peluquería" })
  @ValidateNested({ each: true }) @Type(() => ServicioPeluqueriaDto)
  servicios!: ServicioPeluqueriaDto[];

  @IsOptional() @IsUUID() sede_id?: string;
  @IsOptional() @IsUUID() cita_id?: string;
  @IsOptional() @IsUUID() peluquero_id?: string;
  /** La hora que se le promete al propietario. */
  @IsOptional() @IsDateString() entrega_estimada?: string;
  @IsOptional() @IsNumber() @Min(0) peso_kg?: number;
  @IsOptional() @IsString() @MaxLength(40) condicion_pelaje?: string;
  @IsOptional() @IsString() @MaxLength(40) temperamento?: string;
  @IsOptional() @IsString() @MaxLength(1000) observaciones_ingreso?: string;
  /** storage_key de la foto de recepción. */
  @IsOptional() @IsString() foto_ingreso?: string;
  /** Autoriza rapar si el nudo no se puede desenredar sin dolor. */
  @IsOptional() @IsBoolean() autoriza_rapado?: boolean;
}
