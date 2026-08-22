import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Put } from "@nestjs/common";
import { RolesService } from "./roles.service";
import { CrearRolDto } from "./dto/crear-rol.dto";
import { SetPermisosDto } from "./dto/set-permisos.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("roles")
export class RolesController {
  constructor(private readonly roles: RolesService) {}

  @Get()
  async listar(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.roles.listarRoles(u) };
  }

  /** Permisos agrupados por módulo: la UI arma la matriz directamente. */
  @Get("permisos")
  async permisos(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.roles.listarPermisos(u) };
  }

  @Post()
  async crear(@CurrentUser() u: JwtPayload, @Body() dto: CrearRolDto) {
    return { ok: true, data: await this.roles.crear(u, dto) };
  }

  @Put(":id/permisos")
  async setPermisos(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: SetPermisosDto,
  ) {
    return { ok: true, data: await this.roles.setPermisos(u, id, dto.codigos) };
  }

  @Delete(":id")
  async eliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.roles.eliminar(u, id) };
  }
}
