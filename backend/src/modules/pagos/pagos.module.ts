import { Module } from "@nestjs/common";
import { CajaController, PagosController } from "./pagos.controller";
import { PagosService } from "./pagos.service";
import { PagosRepository } from "./pagos.repository";

@Module({
  controllers: [PagosController, CajaController],
  providers: [PagosService, PagosRepository],
})
export class PagosModule {}
