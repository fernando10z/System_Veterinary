import { Module } from "@nestjs/common";
import { PortalController } from "./portal.controller";
import { PortalService } from "./portal.service";
import { PortalRepository } from "./portal.repository";
import { PortalAuthGuard } from "../../common/guards/portal-auth.guard";

@Module({
  controllers: [PortalController],
  providers: [PortalService, PortalRepository, PortalAuthGuard],
})
export class PortalModule {}
