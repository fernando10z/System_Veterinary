import {
  Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query,
} from "@nestjs/common";
import { MascotasService } from "./mascotas.service";
import { CrearMascotaDto } from "./dto/crear-mascota.dto";
import { ActualizarMascotaDto } from "./dto/actualizar-mascota.dto";
import { ReportarExtravioDto } from "./dto/reportar-extravio.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("mascotas")
export class MascotasController {
  constructor(private readonly mascotas: MascotasService) {}

  @Get()
  async listar(
    @CurrentUser() u: JwtPayload,
    @Query("buscar") buscar?: string,
    @Query("estado") estado?: string,
    @Query("especieId") especieId?: string,
    @Query("clienteId") clienteId?: string,
    @Query("sexo") sexo?: string,
    @Query("page") page?: string,
    @Query("pageSize") pageSize?: string,
  ) {
    const filtros: Record<string, unknown> = {};
    if (buscar) filtros.buscar = buscar;
    if (estado) filtros.estado = estado;
    if (especieId) filtros.especie_id = especieId;
    if (clienteId) filtros.cliente_id = clienteId;
    if (sexo) filtros.sexo = sexo;
    const r = await this.mascotas.listar(u, filtros, Number(page ?? 1), Number(pageSize ?? 20));
    return { ok: true, data: r?.data ?? [], meta: r?.meta };
  }

  @Get("extraviadas")
  async extraviadas(@CurrentUser() u: JwtPayload, @Query("todas") todas?: string) {
    return { ok: true, data: await this.mascotas.extraviadas(u, todas !== "true") };
  }

  @Get(":id")
  async obtener(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.mascotas.obtener(u, id) };
  }

  /** Línea de tiempo clínica completa del paciente. */
  @Get(":id/historia")
  async historia(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Query("tipo") tipo?: string,
    @Query("limit") limit?: string,
  ) {
    return {
      ok: true,
      data: await this.mascotas.historia(u, id, tipo ?? null, Number(limit ?? 100)),
    };
  }

  @Get(":id/vacunas")
  async carne(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.mascotas.carneVacunas(u, id) };
  }

  @Get(":id/documentos")
  async documentos(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.mascotas.documentos(u, id) };
  }

  @Post()
  async crear(@CurrentUser() u: JwtPayload, @Body() dto: CrearMascotaDto) {
    return { ok: true, data: await this.mascotas.crear(u, dto) };
  }

  @Patch(":id")
  async actualizar(
    @CurrentUser() u: JwtPayload,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: ActualizarMascotaDto,
  ) {
    return { ok: true, data: await this.mascotas.actualizar(u, id, dto) };
  }

  @Post("extravios")
  async reportarExtravio(@CurrentUser() u: JwtPayload, @Body() dto: ReportarExtravioDto) {
    return { ok: true, data: await this.mascotas.reportarExtravio(u, dto) };
  }

  @Patch("extravios/:id/encontrada")
  async marcarEncontrada(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.mascotas.marcarEncontrada(u, id) };
  }

  @Delete(":id")
  async eliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.mascotas.eliminar(u, id) };
  }
}
