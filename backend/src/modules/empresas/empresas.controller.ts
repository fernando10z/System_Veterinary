import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query } from "@nestjs/common";
import { EmpresasService } from "./empresas.service";
import { GuardarEmpresaDto } from "./dto/guardar-empresa.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("empresas")
export class EmpresasController {
  constructor(private readonly empresas: EmpresasService) {}

  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("buscar") buscar?: string,
    @Query("estado") estado?: string,
  ) {
    const filtros: Record<string, unknown> = {};
    if (buscar) filtros.buscar = buscar;
    if (estado) filtros.estado = estado;
    return { ok: true, data: await this.empresas.listar(u, filtros) };
  }

  /** Sede activa del usuario (sin id explícito). */
  @Get("actual")
  async actual(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.empresas.obtener(u) };
  }

  @Get(":id")
  async obtener(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.empresas.obtener(u, id) };
  }

  @Post()
  async crear(@CurrentUser() u: JwtPayload, @Body() dto: GuardarEmpresaDto) {
    return { ok: true, data: await this.empresas.crear(u, dto) };
  }

  @Patch(":id")
  async actualizar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: GuardarEmpresaDto,
  ) {
    return { ok: true, data: await this.empresas.actualizar(u, id, dto) };
  }
}
