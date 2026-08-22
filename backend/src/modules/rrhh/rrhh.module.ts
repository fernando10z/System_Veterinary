import { Module } from "@nestjs/common";
import { RrhhController } from "./rrhh.controller";
import { RrhhService } from "./rrhh.service";
import { RrhhRepository } from "./rrhh.repository";

@Module({
  controllers: [RrhhController],
  providers: [RrhhService, RrhhRepository],
})
export class RrhhModule {}
