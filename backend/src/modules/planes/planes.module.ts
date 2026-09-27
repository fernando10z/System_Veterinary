import { Module } from "@nestjs/common";
import { PlanesController } from "./planes.controller";
import { PlanesService } from "./planes.service";
import { PlanesRepository } from "./planes.repository";

@Module({
  controllers: [PlanesController],
  providers: [PlanesService, PlanesRepository],
})
export class PlanesModule {}
