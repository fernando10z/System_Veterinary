import { IsNumber, IsOptional, IsUUID, Min } from "class-validator";

export class ConsumirInsumoDto {
  @IsUUID() producto_id!: string;
  @IsNumber() @Min(0.01) cantidad!: number;
  @IsOptional() @IsUUID() mascota_id?: string;
  @IsOptional() @IsUUID() consulta_id?: string;
  @IsOptional() @IsUUID() cirugia_id?: string;
  @IsOptional() @IsUUID() hospitalizacion_id?: string;
  @IsOptional() @IsUUID() orden_servicio_id?: string;
  @IsOptional() @IsUUID() almacen_id?: string;
  @IsOptional() @IsNumber() @Min(0) precio_unitario?: number;
}
