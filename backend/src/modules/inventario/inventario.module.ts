import { Module } from "@nestjs/common";
import { InventarioController } from "./inventario.controller";
import { InventarioService } from "./inventario.service";
import { InventarioRepository } from "./inventario.repository";

@Module({
  controllers: [InventarioController],
  providers: [InventarioService, InventarioRepository],
})
export class InventarioModule {}
