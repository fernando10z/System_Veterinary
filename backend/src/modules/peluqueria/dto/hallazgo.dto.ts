import { IsBoolean, IsIn, IsOptional, IsString, MaxLength } from "class-validator";

const HALLAZGOS = [
  "pulgas", "garrapatas", "nudos_severos", "heridas", "otitis", "mal_olor_oidos",
  "problemas_piel", "bultos", "unias_encarnadas", "sarro", "secrecion_ocular",
  "delgadez", "agresividad", "otro",
];

/** Lo que el peluquero encuentra al bañar y cepillar. */
export class HallazgoDto {
  @IsIn(HALLAZGOS, { message: "Ese tipo de hallazgo no está en la lista" })
  hallazgo!: string;
  @IsOptional() @IsString() @MaxLength(80) zona?: string;
  @IsOptional() @IsString() @MaxLength(1000) detalle?: string;
  /** Marca lo que no puede esperar a la próxima visita: avisa al veterinario. */
  @IsOptional() @IsBoolean() requiere_veterinario?: boolean;
}
