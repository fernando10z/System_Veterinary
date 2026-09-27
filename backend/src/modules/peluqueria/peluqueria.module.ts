import { Module } from "@nestjs/common";
import { PeluqueriaController } from "./peluqueria.controller";
import { PeluqueriaService } from "./peluqueria.service";
import { PeluqueriaRepository } from "./peluqueria.repository";

@Module({
  controllers: [PeluqueriaController],
  providers: [PeluqueriaService, PeluqueriaRepository],
})
export class PeluqueriaModule {}
