import { Module } from "@nestjs/common";
import { EmpresasController } from "./empresas.controller";
import { EmpresasService } from "./empresas.service";
import { EmpresasRepository } from "./empresas.repository";

@Module({
  controllers: [EmpresasController],
  providers: [EmpresasService, EmpresasRepository],
})
export class EmpresasModule {}
