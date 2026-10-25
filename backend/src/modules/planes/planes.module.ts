import { Module } from "@nestjs/common";
import { PlanesController } from "./planes.controller";
import { PlanesService } from "./planes.service";
import { PlanesRepository } from "./planes.repository";
import { TareasDiariasService } from "./tareas-diarias.service";

@Module({
  controllers: [PlanesController],
  providers: [PlanesService, PlanesRepository, TareasDiariasService],
})
export class PlanesModule {}
