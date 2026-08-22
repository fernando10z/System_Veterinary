import { Module } from "@nestjs/common";
import { MascotasController } from "./mascotas.controller";
import { MascotasService } from "./mascotas.service";
import { MascotasRepository } from "./mascotas.repository";

@Module({
  controllers: [MascotasController],
  providers: [MascotasService, MascotasRepository],
})
export class MascotasModule {}
