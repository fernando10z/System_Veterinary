import { Module } from "@nestjs/common";
import { FacturacionController } from "./facturacion.controller";
import { FacturacionService } from "./facturacion.service";
import { FacturacionRepository } from "./facturacion.repository";
import { PseService } from "./pse/pse.service";

@Module({
  controllers: [FacturacionController],
  providers: [FacturacionService, FacturacionRepository, PseService],
})
export class FacturacionModule {}
