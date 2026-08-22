import { Module } from "@nestjs/common";
import { AuditoriaController, NotificacionesController } from "./auditoria.controller";
import { AuditoriaService } from "./auditoria.service";
import { AuditoriaRepository } from "./auditoria.repository";

@Module({
  controllers: [AuditoriaController, NotificacionesController],
  providers: [AuditoriaService, AuditoriaRepository],
})
export class AuditoriaModule {}
