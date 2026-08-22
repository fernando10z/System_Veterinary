import {
  Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query,
} from "@nestjs/common";
import { ClientesService } from "./clientes.service";
import { CrearClienteDto } from "./dto/crear-cliente.dto";
import { ActualizarClienteDto } from "./dto/actualizar-cliente.dto";
import { ActivarPortalDto } from "./dto/activar-portal.dto";
import { RegistrarComunicacionDto } from "./dto/registrar-comunicacion.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("clientes")
export class ClientesController {
  constructor(private readonly clientes: ClientesService) {}

  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("buscar") buscar?: string,
    @Query("estado") estado?: string,
    @Query("conPortal") conPortal?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const filtros: Record<string, unknown> = {};
    if (buscar) filtros.buscar = buscar;
    if (estado) filtros.estado = estado;
    if (conPortal === "true" || conPortal === "false") filtros.con_portal = conPortal === "true";
    const r = await this.clientes.listar(u, filtros, Number(page ?? 1), Number(pageSize ?? 20));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  /** Autocompletar de recepción: busca por nombre, documento, teléfono o mascota. */
  @Get("buscar")
  async buscar(
    @CurrentUser() u: JwtPayload,
    @Query("q") q: string,
    @Query("limit") limit?: string,
  ) {
    return { ok: true, data: await this.clientes.buscar(u, q ?? "", Number(limit ?? 20)) };
  }

  @Get("comunicaciones")
  async comunicaciones(
    @CurrentUser() u: JwtPayload,
    @Query("clienteId") clienteId?: string,
    @Query("limit") limit?: string,
  ) {
    return {
      ok: true,
      data: await this.clientes.comunicaciones(u, clienteId ?? null, Number(limit ?? 50)),
    };
  }

  @Post("comunicaciones")
  async registrarComunicacion(
    @CurrentUser() u: JwtPayload,
    @Body() dto: RegistrarComunicacionDto,
  ) {
    return { ok: true, data: await this.clientes.registrarComunicacion(u, dto) };
  }

  @Get(":id")
  async obtener(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.clientes.obtener(u, id) };
  }

  @Post()
  async crear(@CurrentUser() u: JwtPayload, @Body() dto: CrearClienteDto) {
    return { ok: true, data: await this.clientes.crear(u, dto) };
  }

  @Patch(":id")
  async actualizar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ActualizarClienteDto,
  ) {
    return { ok: true, data: await this.clientes.actualizar(u, id, dto) };
  }

  @Post(":id/portal")
  async activarPortal(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ActivarPortalDto,
  ) {
    return { ok: true, data: await this.clientes.activarPortal(u, id, dto.password) };
  }

  @Delete(":id")
  async eliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.clientes.eliminar(u, id) };
  }
}
