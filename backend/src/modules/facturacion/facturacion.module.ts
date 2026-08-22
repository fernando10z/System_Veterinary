import { Module } from "@nestjs/common";
import { FacturacionController } from "./facturacion.controller";
import { FacturacionService } from "./facturacion.service";
import { FacturacionRepository } from "./facturacion.repository";

@Module({
  controllers: [FacturacionController],
  providers: [FacturacionService, FacturacionRepository],
})
export class FacturacionModule {}
