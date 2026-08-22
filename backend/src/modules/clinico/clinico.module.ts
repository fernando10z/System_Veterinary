import { Module } from "@nestjs/common";
import { ClinicoController } from "./clinico.controller";
import { ClinicoService } from "./clinico.service";
import { ClinicoRepository } from "./clinico.repository";

@Module({
  controllers: [ClinicoController],
  providers: [ClinicoService, ClinicoRepository],
  exports: [ClinicoService],
})
export class ClinicoModule {}
