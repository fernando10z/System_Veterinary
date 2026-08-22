import {
  Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query,
} from "@nestjs/common";
import { UsersService } from "./users.service";
import { CrearUsuarioDto } from "./dto/crear-usuario.dto";
import { ActualizarUsuarioDto } from "./dto/actualizar-usuario.dto";
import { CambiarEstadoDto } from "./dto/cambiar-estado.dto";
import { CambiarRolDto } from "./dto/cambiar-rol.dto";
import { ResetPasswordAdminDto } from "./dto/reset-password-admin.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("users")
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("buscar") buscar?: string,
    @Query("estado") estado?: string,
    @Query("rolId") rolId?: string,
    @Query("soloVeterinarios") soloVeterinarios?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const filtros: Record<string, unknown> = {};
    if (buscar) filtros.buscar = buscar;
    if (estado) filtros.estado = estado;
    if (rolId) filtros.rol_id = rolId;
    if (soloVeterinarios === "true") filtros.solo_veterinarios = true;
    const r = await this.users.listar(u, filtros, Number(page ?? 1), Number(pageSize ?? 20));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  /** Atajo para los selects de agenda e historia clínica. */
  @Get("veterinarios")
  async veterinarios(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.users.veterinarios(u) };
  }

  @Get(":id")
  async obtener(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.users.obtener(u, id) };
  }

  @Post()
  async crear(@CurrentUser() u: JwtPayload, @Body() dto: CrearUsuarioDto) {
    return { ok: true, data: await this.users.crear(u, dto) };
  }

  @Patch(":id")
  async actualizar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ActualizarUsuarioDto,
  ) {
    return { ok: true, data: await this.users.actualizar(u, id, dto) };
  }

  @Patch(":id/estado")
  async cambiarEstado(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CambiarEstadoDto,
  ) {
    return { ok: true, data: await this.users.cambiarEstado(u, id, dto.estado) };
  }

  @Patch(":id/rol")
  async cambiarRol(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CambiarRolDto,
  ) {
    return { ok: true, data: await this.users.cambiarRol(u, id, dto.rolId, dto.empresaId) };
  }

  @Post(":id/reset-password")
  async resetPassword(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ResetPasswordAdminDto,
  ) {
    return { ok: true, data: await this.users.resetPassword(u, id, dto.passwordTemp) };
  }

  @Delete(":id")
  async eliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.users.eliminar(u, id) };
  }
}
