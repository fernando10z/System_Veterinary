import { Module } from "@nestjs/common";
import { CatalogosController } from "./catalogos.controller";
import { CatalogosService } from "./catalogos.service";
import { CatalogosRepository } from "./catalogos.repository";

@Module({
  controllers: [CatalogosController],
  providers: [CatalogosService, CatalogosRepository],
})
export class CatalogosModule {}
