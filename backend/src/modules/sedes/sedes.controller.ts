import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Query } from "@nestjs/common";
import { SedesService } from "./sedes.service";
import { GuardarSedeDto } from "./dto/guardar-sede.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

/**
 * Los locales de una misma clínica. Lo que comparten —cartera, historia
 * clínica, catálogo, personal— vive en la empresa; lo que ocupa espacio
 * —agenda, stock, caja, horario— vive en la sede.
 */
@Controller("sedes")
export class SedesController {
  constructor(private readonly sedes: SedesService) {}

  @Get()
  async listar(@CurrentUser() u: JwtPayload, @Query("estado") estado?: string) {
    return { ok: true, data: await this.sedes.listar(u, estado ? { estado } : {}) };
  }

  @Post()
  async guardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarSedeDto) {
    return { ok: true, data: await this.sedes.guardar(u, { ...dto }) };
  }

  @Delete(":id")
  async eliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.sedes.eliminar(u, id) };
  }
}
